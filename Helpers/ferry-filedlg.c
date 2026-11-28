
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <commdlg.h>
#include <dlgs.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <shlwapi.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>

DEFINE_GUID(CLSID_FerryFileOpenDialog, 0xdc1c5a9c, 0xe88a, 0x4dde, 0xa5, 0xa1, 0x60, 0xf8, 0x2a, 0x20, 0xae, 0xf7);
DEFINE_GUID(CLSID_FerryFileSaveDialog, 0xc0b4e2f3, 0xba21, 0x4773, 0x8d, 0xba, 0x33, 0x5e, 0xc9, 0x46, 0xeb, 0x8b);

static void note(const char *format, ...) {
    char path[MAX_PATH];
    DWORD n = GetEnvironmentVariableA("FERRY_FILEDLG_LOG", path, sizeof path);
    if (!n || n >= sizeof path) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    va_list args;
    va_start(args, format);
    fprintf(f, "[%lu] ", GetCurrentThreadId());
    vfprintf(f, format, args);
    fputc('\n', f);
    va_end(args);
    fclose(f);
}

static const char *narrow(const WCHAR *text) {
    static char buffer[1024];
    if (!text) return "(none)";
    WideCharToMultiByte(CP_UTF8, 0, text, -1, buffer, sizeof buffer, NULL, NULL);
    return buffer;
}

static WCHAR *copy(const WCHAR *text) {
    if (!text) return NULL;
    size_t bytes = (wcslen(text) + 1) * sizeof(WCHAR);
    WCHAR *out = HeapAlloc(GetProcessHeap(), 0, bytes);
    if (out) memcpy(out, text, bytes);
    return out;
}

static void drop(WCHAR **text) {
    if (*text) HeapFree(GetProcessHeap(), 0, *text);
    *text = NULL;
}

static void replace(WCHAR **text, const WCHAR *with) {
    drop(text);
    *text = copy(with);
}

static WCHAR *item_path(IShellItem *item) {
    WCHAR *path = NULL;
    if (!item || FAILED(IShellItem_GetDisplayName(item, SIGDN_FILESYSPATH, &path))) return NULL;
    return path;
}

static HRESULT path_item(const WCHAR *path, REFIID riid, void **out) {
    *out = NULL;
    PIDLIST_ABSOLUTE pidl = SHSimpleIDListFromPath(path);
    if (!pidl) return E_FAIL;
    HRESULT hr = SHCreateItemFromIDList(pidl, riid, out);
    CoTaskMemFree(pidl);
    return hr;
}

static void downloads_folder(WCHAR *out, DWORD size) {
    WCHAR value[MAX_PATH], candidate[MAX_PATH];
    out[0] = 0;
    DWORD n = GetEnvironmentVariableW(L"WINEHOMEDIR", value, MAX_PATH);
    if (n && n < MAX_PATH) {
        const WCHAR *home = wcsncmp(value, L"\\??\\", 4) ? value : value + 4;
        _snwprintf(candidate, MAX_PATH, L"%ls\\Downloads", home);
        candidate[MAX_PATH - 1] = 0;
        DWORD attributes = GetFileAttributesW(candidate);
        if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY)) {
            lstrcpynW(out, candidate, size);
            return;
        }
    }
    n = GetEnvironmentVariableW(L"USERNAME", value, MAX_PATH);
    if (n && n < MAX_PATH) {
        _snwprintf(candidate, MAX_PATH, L"Z:\\Users\\%ls\\Downloads", value);
        candidate[MAX_PATH - 1] = 0;
        DWORD attributes = GetFileAttributesW(candidate);
        if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY)) lstrcpynW(out, candidate, size);
    }
}

enum { MAX_SINKS = 8, MAX_CONTROLS = 32, FILE_BUFFER = 32768, FIRST_CONTROL_ID = 0x4100 };
enum ControlKind { CHECK, TEXT, SEPARATOR, GROUP };

typedef struct {
    DWORD id;
    enum ControlKind kind;
    WCHAR *label;
    BOOL checked;
    CDCONTROLSTATEF state;
} Control;

typedef struct {
    IFileDialog dialog;
    IFileDialogCustomize customize;
    IOleWindow window;
    LONG refs;
    BOOL save;
    IFileDialog *real;
    IFileDialogCustomize *realCustomize;
    const char *wineOnly;

    WCHAR *filter;
    WCHAR *title, *okLabel, *nameLabel, *defaultExtension;
    IShellItem *folder, *defaultFolder, *saveAs;

    struct { DWORD cookie; IFileDialogEvents *sink; } sinks[MAX_SINKS];
    int sinkCount;
    Control controls[MAX_CONTROLS];
    int controlCount;

    HWND hwnd, child;
    OPENFILENAMEW *ofn;
    WCHAR **results;
    UINT resultCount;
    BOOL closed;
    HRESULT closeResult;
} Dlg;

static Dlg *from_dialog(IFileDialog *iface) { return CONTAINING_RECORD(iface, Dlg, dialog); }
static Dlg *from_customize(IFileDialogCustomize *iface) { return CONTAINING_RECORD(iface, Dlg, customize); }
static Dlg *from_window(IOleWindow *iface) { return CONTAINING_RECORD(iface, Dlg, window); }

static void wine_only(Dlg *d, const char *why) {
    if (!d->wineOnly) note("Wine's item dialog from now on: %s", why);
    d->wineOnly = why;
}

static void clear_results(Dlg *d) {
    for (UINT i = 0; i < d->resultCount; i++) HeapFree(GetProcessHeap(), 0, d->results[i]);
    if (d->results) HeapFree(GetProcessHeap(), 0, d->results);
    d->results = NULL;
    d->resultCount = 0;
}

static void set_item(IShellItem **slot, IShellItem *item) {
    if (item) IShellItem_AddRef(item);
    if (*slot) IShellItem_Release(*slot);
    *slot = item;
}

static HRESULT WINAPI dlg_QueryInterface(IFileDialog *iface, REFIID riid, void **out) {
    Dlg *d = from_dialog(iface);
    *out = NULL;
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IModalWindow) || IsEqualIID(riid, &IID_IFileDialog) ||
        IsEqualIID(riid, d->save ? &IID_IFileSaveDialog : &IID_IFileOpenDialog)) {
        *out = &d->dialog;
    } else if (IsEqualIID(riid, &IID_IFileDialogCustomize)) {
        if (!d->realCustomize &&
            FAILED(IFileDialog_QueryInterface(d->real, &IID_IFileDialogCustomize, (void **)&d->realCustomize)))
            return E_NOINTERFACE;
        *out = &d->customize;
    } else if (IsEqualIID(riid, &IID_IOleWindow)) {
        *out = &d->window;
    } else {
        HRESULT hr = IFileDialog_QueryInterface(d->real, riid, out);
        if (SUCCEEDED(hr)) wine_only(d, "the program asked for an interface only Wine's dialog has");
        return hr;
    }
    IUnknown_AddRef((IUnknown *)*out);
    return S_OK;
}

static ULONG WINAPI dlg_AddRef(IFileDialog *iface) { return InterlockedIncrement(&from_dialog(iface)->refs); }

static ULONG WINAPI dlg_Release(IFileDialog *iface) {
    Dlg *d = from_dialog(iface);
    ULONG refs = InterlockedDecrement(&d->refs);
    if (refs) return refs;
    for (int i = 0; i < d->sinkCount; i++) IFileDialogEvents_Release(d->sinks[i].sink);
    for (int i = 0; i < d->controlCount; i++) drop(&d->controls[i].label);
    set_item(&d->folder, NULL);
    set_item(&d->defaultFolder, NULL);
    set_item(&d->saveAs, NULL);
    drop(&d->filter);
    drop(&d->title);
    drop(&d->okLabel);
    drop(&d->nameLabel);
    drop(&d->defaultExtension);
    clear_results(d);
    if (d->realCustomize) IFileDialogCustomize_Release(d->realCustomize);
    IFileDialog_Release(d->real);
    HeapFree(GetProcessHeap(), 0, d);
    return 0;
}

static HRESULT show_explorer_dialog(Dlg *d, HWND owner);

static HRESULT WINAPI dlg_Show(IFileDialog *iface, HWND owner) {
    Dlg *d = from_dialog(iface);
    FILEOPENDIALOGOPTIONS options = 0;
    IFileDialog_GetOptions(d->real, &options);
    if (options & FOS_PICKFOLDERS) wine_only(d, "it picks a folder");
    else if (options & FOS_ALLNONSTORAGEITEMS) wine_only(d, "it picks items that aren't files");
    if (d->wineOnly) {
        note("Show: Wine's item dialog (%s)", d->wineOnly);
        clear_results(d);
        return IFileDialog_Show(d->real, owner);
    }
    return show_explorer_dialog(d, owner);
}

static HRESULT WINAPI dlg_SetFileTypes(IFileDialog *iface, UINT count, const COMDLG_FILTERSPEC *specs) {
    Dlg *d = from_dialog(iface);
    HRESULT hr = IFileDialog_SetFileTypes(d->real, count, specs);
    if (FAILED(hr)) return hr;
    size_t length = 1;
    for (UINT i = 0; i < count; i++)
        length += wcslen(specs[i].pszName ? specs[i].pszName : L"") + wcslen(specs[i].pszSpec ? specs[i].pszSpec : L"") + 2;
    drop(&d->filter);
    WCHAR *out = d->filter = HeapAlloc(GetProcessHeap(), 0, length * sizeof(WCHAR));
    if (!out) return hr;
    for (UINT i = 0; i < count; i++) {
        const WCHAR *spec = specs[i].pszSpec ? specs[i].pszSpec : L"";
        const WCHAR *name = specs[i].pszName && specs[i].pszName[0] ? specs[i].pszName : spec;
        wcscpy(out, name);
        out += wcslen(name) + 1;
        wcscpy(out, spec);
        out += wcslen(spec) + 1;
    }
    *out = 0;
    return hr;
}

static HRESULT WINAPI dlg_SetFileTypeIndex(IFileDialog *iface, UINT index) {
    Dlg *d = from_dialog(iface);
    if (d->hwnd) {
        HWND types = GetDlgItem(d->hwnd, cmb1);
        if (types && index) SendMessageW(types, CB_SETCURSEL, index - 1, 0);
        if (d->ofn && index) d->ofn->nFilterIndex = index;
    }
    return IFileDialog_SetFileTypeIndex(d->real, index);
}

static HRESULT WINAPI dlg_GetFileTypeIndex(IFileDialog *iface, UINT *index) {
    Dlg *d = from_dialog(iface);
    if (d->hwnd && index) {
        HWND types = GetDlgItem(d->hwnd, cmb1);
        LRESULT selected = types ? SendMessageW(types, CB_GETCURSEL, 0, 0) : CB_ERR;
        if (selected != CB_ERR) {
            *index = (UINT)selected + 1;
            return S_OK;
        }
    }
    return IFileDialog_GetFileTypeIndex(d->real, index);
}

static HRESULT WINAPI dlg_Advise(IFileDialog *iface, IFileDialogEvents *sink, DWORD *cookie) {
    Dlg *d = from_dialog(iface);
    if (!sink || !cookie) return E_INVALIDARG;
    if (d->sinkCount == MAX_SINKS) wine_only(d, "too many event handlers");
    HRESULT hr = IFileDialog_Advise(d->real, sink, cookie);
    if (FAILED(hr) || d->sinkCount == MAX_SINKS) return hr;
    IFileDialogEvents_AddRef(sink);
    d->sinks[d->sinkCount].cookie = *cookie;
    d->sinks[d->sinkCount].sink = sink;
    d->sinkCount++;
    return hr;
}

static HRESULT WINAPI dlg_Unadvise(IFileDialog *iface, DWORD cookie) {
    Dlg *d = from_dialog(iface);
    for (int i = 0; i < d->sinkCount; i++) {
        if (d->sinks[i].cookie != cookie) continue;
        IFileDialogEvents_Release(d->sinks[i].sink);
        d->sinks[i] = d->sinks[--d->sinkCount];
        break;
    }
    return IFileDialog_Unadvise(d->real, cookie);
}

static HRESULT WINAPI dlg_SetOptions(IFileDialog *iface, FILEOPENDIALOGOPTIONS options) {
    return IFileDialog_SetOptions(from_dialog(iface)->real, options);
}

static HRESULT WINAPI dlg_GetOptions(IFileDialog *iface, FILEOPENDIALOGOPTIONS *options) {
    return IFileDialog_GetOptions(from_dialog(iface)->real, options);
}

static HRESULT WINAPI dlg_SetDefaultFolder(IFileDialog *iface, IShellItem *item) {
    Dlg *d = from_dialog(iface);
    HRESULT hr = IFileDialog_SetDefaultFolder(d->real, item);
    if (SUCCEEDED(hr)) set_item(&d->defaultFolder, item);
    return hr;
}

static HRESULT WINAPI dlg_SetFolder(IFileDialog *iface, IShellItem *item) {
    Dlg *d = from_dialog(iface);
    HRESULT hr = IFileDialog_SetFolder(d->real, item);
    if (SUCCEEDED(hr)) set_item(&d->folder, item);
    if (d->hwnd && item) {
        WCHAR *path = item_path(item);
        if (path) {
            SendMessageW(d->hwnd, CDM_SETCONTROLTEXT, cmb13, (LPARAM)path);
            SendMessageW(d->hwnd, CDM_SETCONTROLTEXT, edt1, (LPARAM)path);
            PostMessageW(d->hwnd, WM_COMMAND, MAKEWPARAM(IDOK, BN_CLICKED), (LPARAM)GetDlgItem(d->hwnd, IDOK));
            CoTaskMemFree(path);
        }
    }
    return hr;
}

static WCHAR *live_text(Dlg *d, UINT message) {
    if (!d->hwnd) return NULL;
    LRESULT length = SendMessageW(d->hwnd, message, 0, 0);
    if (length <= 0) return NULL;
    WCHAR *text = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, (length + 1) * sizeof(WCHAR));
    if (text && SendMessageW(d->hwnd, message, length + 1, (LPARAM)text) <= 0) {
        HeapFree(GetProcessHeap(), 0, text);
        text = NULL;
    }
    return text;
}

static HRESULT WINAPI dlg_GetFolder(IFileDialog *iface, IShellItem **item) {
    Dlg *d = from_dialog(iface);
    if (!item) return E_INVALIDARG;
    WCHAR *now = live_text(d, CDM_GETFOLDERPATH);
    if (now) {
        HRESULT hr = path_item(now, &IID_IShellItem, (void **)item);
        HeapFree(GetProcessHeap(), 0, now);
        if (SUCCEEDED(hr)) return hr;
    }
    return IFileDialog_GetFolder(d->real, item);
}

static HRESULT WINAPI dlg_GetCurrentSelection(IFileDialog *iface, IShellItem **item) {
    Dlg *d = from_dialog(iface);
    if (!item) return E_INVALIDARG;
    WCHAR *now = live_text(d, CDM_GETFILEPATH);
    if (now) {
        HRESULT hr = path_item(now, &IID_IShellItem, (void **)item);
        HeapFree(GetProcessHeap(), 0, now);
        return hr;
    }
    if (d->hwnd) {
        *item = NULL;
        return E_FAIL;
    }
    return IFileDialog_GetCurrentSelection(d->real, item);
}

static HRESULT WINAPI dlg_SetFileName(IFileDialog *iface, LPCWSTR name) {
    Dlg *d = from_dialog(iface);
    if (d->hwnd) {
        SendMessageW(d->hwnd, CDM_SETCONTROLTEXT, cmb13, (LPARAM)(name ? name : L""));
        SendMessageW(d->hwnd, CDM_SETCONTROLTEXT, edt1, (LPARAM)(name ? name : L""));
    }
    return IFileDialog_SetFileName(d->real, name);
}

static HRESULT WINAPI dlg_GetFileName(IFileDialog *iface, LPWSTR *name) {
    Dlg *d = from_dialog(iface);
    if (!name) return E_INVALIDARG;
    if (d->hwnd) {
        WCHAR *now = live_text(d, CDM_GETSPEC);
        *name = CoTaskMemAlloc(((now ? wcslen(now) : 0) + 1) * sizeof(WCHAR));
        if (*name) wcscpy(*name, now ? now : L"");
        if (now) HeapFree(GetProcessHeap(), 0, now);
        return *name ? S_OK : E_OUTOFMEMORY;
    }
    return IFileDialog_GetFileName(d->real, name);
}

static HRESULT WINAPI dlg_SetTitle(IFileDialog *iface, LPCWSTR title) {
    Dlg *d = from_dialog(iface);
    replace(&d->title, title);
    if (d->hwnd) SetWindowTextW(d->hwnd, title ? title : L"");
    return IFileDialog_SetTitle(d->real, title);
}

static HRESULT WINAPI dlg_SetOkButtonLabel(IFileDialog *iface, LPCWSTR text) {
    Dlg *d = from_dialog(iface);
    replace(&d->okLabel, text);
    if (d->hwnd && text) SendMessageW(d->hwnd, CDM_SETCONTROLTEXT, IDOK, (LPARAM)text);
    return IFileDialog_SetOkButtonLabel(d->real, text);
}

static HRESULT WINAPI dlg_SetFileNameLabel(IFileDialog *iface, LPCWSTR text) {
    Dlg *d = from_dialog(iface);
    replace(&d->nameLabel, text);
    if (d->hwnd && text) SendMessageW(d->hwnd, CDM_SETCONTROLTEXT, stc3, (LPARAM)text);
    return IFileDialog_SetFileNameLabel(d->real, text);
}

static HRESULT WINAPI dlg_GetResult(IFileDialog *iface, IShellItem **item) {
    Dlg *d = from_dialog(iface);
    if (!item) return E_INVALIDARG;
    if (d->resultCount) return path_item(d->results[0], &IID_IShellItem, (void **)item);
    return IFileDialog_GetResult(d->real, item);
}

static HRESULT WINAPI dlg_AddPlace(IFileDialog *iface, IShellItem *item, FDAP where) {
    return IFileDialog_AddPlace(from_dialog(iface)->real, item, where);
}

static HRESULT WINAPI dlg_SetDefaultExtension(IFileDialog *iface, LPCWSTR extension) {
    Dlg *d = from_dialog(iface);
    replace(&d->defaultExtension, extension);
    return IFileDialog_SetDefaultExtension(d->real, extension);
}

static HRESULT WINAPI dlg_Close(IFileDialog *iface, HRESULT result) {
    Dlg *d = from_dialog(iface);
    if (!d->hwnd) return IFileDialog_Close(d->real, result);
    d->closed = TRUE;
    d->closeResult = result;
    PostMessageW(d->hwnd, WM_COMMAND, MAKEWPARAM(IDCANCEL, BN_CLICKED), (LPARAM)GetDlgItem(d->hwnd, IDCANCEL));
    return S_OK;
}

static HRESULT WINAPI dlg_SetClientGuid(IFileDialog *iface, REFGUID guid) {
    return IFileDialog_SetClientGuid(from_dialog(iface)->real, guid);
}

static HRESULT WINAPI dlg_ClearClientData(IFileDialog *iface) {
    return IFileDialog_ClearClientData(from_dialog(iface)->real);
}

static HRESULT WINAPI dlg_SetFilter(IFileDialog *iface, IShellItemFilter *filter) {
    Dlg *d = from_dialog(iface);
    HRESULT hr = IFileDialog_SetFilter(d->real, filter);
    if (filter) wine_only(d, "it filters the items itself");
    return hr;
}

static HRESULT WINAPI open_GetResults(IFileOpenDialog *iface, IShellItemArray **items) {
    Dlg *d = from_dialog((IFileDialog *)iface);
    if (!items) return E_INVALIDARG;
    if (!d->resultCount) return IFileOpenDialog_GetResults((IFileOpenDialog *)d->real, items);
    PIDLIST_ABSOLUTE *pidls = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, d->resultCount * sizeof *pidls);
    if (!pidls) return E_OUTOFMEMORY;
    HRESULT hr = S_OK;
    for (UINT i = 0; i < d->resultCount && SUCCEEDED(hr); i++)
        if (!(pidls[i] = SHSimpleIDListFromPath(d->results[i]))) hr = E_FAIL;
    if (SUCCEEDED(hr)) hr = SHCreateShellItemArrayFromIDLists(d->resultCount, (PCIDLIST_ABSOLUTE_ARRAY)pidls, items);
    for (UINT i = 0; i < d->resultCount; i++) CoTaskMemFree(pidls[i]);
    HeapFree(GetProcessHeap(), 0, pidls);
    return hr;
}

static HRESULT WINAPI open_GetSelectedItems(IFileOpenDialog *iface, IShellItemArray **items) {
    Dlg *d = from_dialog((IFileDialog *)iface);
    if (d->hwnd) {
        IShellItem *item = NULL;
        HRESULT hr = dlg_GetCurrentSelection(&d->dialog, &item);
        if (FAILED(hr)) return hr;
        hr = SHCreateShellItemArrayFromShellItem(item, &IID_IShellItemArray, (void **)items);
        IShellItem_Release(item);
        return hr;
    }
    return IFileOpenDialog_GetSelectedItems((IFileOpenDialog *)d->real, items);
}

static HRESULT WINAPI save_SetSaveAsItem(IFileSaveDialog *iface, IShellItem *item) {
    Dlg *d = from_dialog((IFileDialog *)iface);
    HRESULT hr = IFileSaveDialog_SetSaveAsItem((IFileSaveDialog *)d->real, item);
    if (SUCCEEDED(hr)) set_item(&d->saveAs, item);
    return hr;
}

static HRESULT WINAPI save_SetProperties(IFileSaveDialog *iface, IPropertyStore *store) {
    return IFileSaveDialog_SetProperties((IFileSaveDialog *)from_dialog((IFileDialog *)iface)->real, store);
}

static HRESULT WINAPI save_SetCollectedProperties(IFileSaveDialog *iface, IPropertyDescriptionList *list, BOOL append) {
    return IFileSaveDialog_SetCollectedProperties((IFileSaveDialog *)from_dialog((IFileDialog *)iface)->real, list, append);
}

static HRESULT WINAPI save_GetProperties(IFileSaveDialog *iface, IPropertyStore **store) {
    return IFileSaveDialog_GetProperties((IFileSaveDialog *)from_dialog((IFileDialog *)iface)->real, store);
}

static HRESULT WINAPI save_ApplyProperties(IFileSaveDialog *iface, IShellItem *item, IPropertyStore *store, HWND owner,
                                           IFileOperationProgressSink *sink) {
    return IFileSaveDialog_ApplyProperties((IFileSaveDialog *)from_dialog((IFileDialog *)iface)->real, item, store, owner, sink);
}

#define DIALOG_METHODS                                                                                                   \
    .QueryInterface = (void *)dlg_QueryInterface, .AddRef = (void *)dlg_AddRef, .Release = (void *)dlg_Release,         \
    .Show = (void *)dlg_Show, .SetFileTypes = (void *)dlg_SetFileTypes, .SetFileTypeIndex = (void *)dlg_SetFileTypeIndex, \
    .GetFileTypeIndex = (void *)dlg_GetFileTypeIndex, .Advise = (void *)dlg_Advise, .Unadvise = (void *)dlg_Unadvise,   \
    .SetOptions = (void *)dlg_SetOptions, .GetOptions = (void *)dlg_GetOptions,                                          \
    .SetDefaultFolder = (void *)dlg_SetDefaultFolder, .SetFolder = (void *)dlg_SetFolder,                               \
    .GetFolder = (void *)dlg_GetFolder, .GetCurrentSelection = (void *)dlg_GetCurrentSelection,                         \
    .SetFileName = (void *)dlg_SetFileName, .GetFileName = (void *)dlg_GetFileName, .SetTitle = (void *)dlg_SetTitle,   \
    .SetOkButtonLabel = (void *)dlg_SetOkButtonLabel, .SetFileNameLabel = (void *)dlg_SetFileNameLabel,                 \
    .GetResult = (void *)dlg_GetResult, .AddPlace = (void *)dlg_AddPlace,                                               \
    .SetDefaultExtension = (void *)dlg_SetDefaultExtension, .Close = (void *)dlg_Close,                                 \
    .SetClientGuid = (void *)dlg_SetClientGuid, .ClearClientData = (void *)dlg_ClearClientData,                         \
    .SetFilter = (void *)dlg_SetFilter

static const IFileOpenDialogVtbl openVtbl = {
    DIALOG_METHODS, .GetResults = open_GetResults, .GetSelectedItems = open_GetSelectedItems,
};

static const IFileSaveDialogVtbl saveVtbl = {
    DIALOG_METHODS, .SetSaveAsItem = save_SetSaveAsItem, .SetProperties = save_SetProperties,
    .SetCollectedProperties = save_SetCollectedProperties, .GetProperties = save_GetProperties,
    .ApplyProperties = save_ApplyProperties,
};

static HRESULT WINAPI win_QueryInterface(IOleWindow *iface, REFIID riid, void **out) {
    return dlg_QueryInterface(&from_window(iface)->dialog, riid, out);
}
static ULONG WINAPI win_AddRef(IOleWindow *iface) { return dlg_AddRef(&from_window(iface)->dialog); }
static ULONG WINAPI win_Release(IOleWindow *iface) { return dlg_Release(&from_window(iface)->dialog); }

static HRESULT WINAPI win_GetWindow(IOleWindow *iface, HWND *hwnd) {
    Dlg *d = from_window(iface);
    if (!hwnd) return E_INVALIDARG;
    if (d->hwnd) {
        *hwnd = d->hwnd;
        return S_OK;
    }
    IOleWindow *real = NULL;
    HRESULT hr = IFileDialog_QueryInterface(d->real, &IID_IOleWindow, (void **)&real);
    if (FAILED(hr)) return hr;
    hr = IOleWindow_GetWindow(real, hwnd);
    IOleWindow_Release(real);
    return hr;
}

static HRESULT WINAPI win_ContextSensitiveHelp(IOleWindow *iface, BOOL enter) { return E_NOTIMPL; }

static const IOleWindowVtbl windowVtbl = {
    win_QueryInterface, win_AddRef, win_Release, win_GetWindow, win_ContextSensitiveHelp,
};

static Control *control(Dlg *d, DWORD id) {
    for (int i = 0; i < d->controlCount; i++)
        if (d->controls[i].id == id) return &d->controls[i];
    return NULL;
}

static HWND control_window(Dlg *d, Control *c) {
    return d->child ? GetDlgItem(d->child, FIRST_CONTROL_ID + (int)(c - d->controls)) : NULL;
}

static void add_control(Dlg *d, DWORD id, enum ControlKind kind, LPCWSTR label, BOOL checked) {
    if (d->controlCount == MAX_CONTROLS) {
        wine_only(d, "too many added controls");
        return;
    }
    Control *c = &d->controls[d->controlCount++];
    c->id = id;
    c->kind = kind;
    c->label = copy(label ? label : L"");
    c->checked = checked;
    c->state = CDCS_ENABLEDVISIBLE;
}

static HRESULT WINAPI cus_QueryInterface(IFileDialogCustomize *iface, REFIID riid, void **out) {
    return dlg_QueryInterface(&from_customize(iface)->dialog, riid, out);
}
static ULONG WINAPI cus_AddRef(IFileDialogCustomize *iface) { return dlg_AddRef(&from_customize(iface)->dialog); }
static ULONG WINAPI cus_Release(IFileDialogCustomize *iface) { return dlg_Release(&from_customize(iface)->dialog); }

#define REAL(d) ((d)->realCustomize)

static HRESULT WINAPI cus_EnableOpenDropDown(IFileDialogCustomize *iface, DWORD id) {
    Dlg *d = from_customize(iface);
    wine_only(d, "it adds a drop-down to the Open button");
    return IFileDialogCustomize_EnableOpenDropDown(REAL(d), id);
}
static HRESULT WINAPI cus_AddMenu(IFileDialogCustomize *iface, DWORD id, LPCWSTR label) {
    Dlg *d = from_customize(iface);
    wine_only(d, "it adds a menu");
    return IFileDialogCustomize_AddMenu(REAL(d), id, label);
}
static HRESULT WINAPI cus_AddPushButton(IFileDialogCustomize *iface, DWORD id, LPCWSTR label) {
    Dlg *d = from_customize(iface);
    wine_only(d, "it adds a button");
    return IFileDialogCustomize_AddPushButton(REAL(d), id, label);
}
static HRESULT WINAPI cus_AddComboBox(IFileDialogCustomize *iface, DWORD id) {
    Dlg *d = from_customize(iface);
    wine_only(d, "it adds a drop-down list");
    return IFileDialogCustomize_AddComboBox(REAL(d), id);
}
static HRESULT WINAPI cus_AddRadioButtonList(IFileDialogCustomize *iface, DWORD id) {
    Dlg *d = from_customize(iface);
    wine_only(d, "it adds radio buttons");
    return IFileDialogCustomize_AddRadioButtonList(REAL(d), id);
}
static HRESULT WINAPI cus_AddEditBox(IFileDialogCustomize *iface, DWORD id, LPCWSTR text) {
    Dlg *d = from_customize(iface);
    wine_only(d, "it adds a text box");
    return IFileDialogCustomize_AddEditBox(REAL(d), id, text);
}

static HRESULT WINAPI cus_AddCheckButton(IFileDialogCustomize *iface, DWORD id, LPCWSTR label, BOOL checked) {
    Dlg *d = from_customize(iface);
    HRESULT hr = IFileDialogCustomize_AddCheckButton(REAL(d), id, label, checked);
    if (SUCCEEDED(hr)) add_control(d, id, CHECK, label, checked);
    return hr;
}
static HRESULT WINAPI cus_AddSeparator(IFileDialogCustomize *iface, DWORD id) {
    Dlg *d = from_customize(iface);
    HRESULT hr = IFileDialogCustomize_AddSeparator(REAL(d), id);
    if (SUCCEEDED(hr)) add_control(d, id, SEPARATOR, NULL, FALSE);
    return hr;
}
static HRESULT WINAPI cus_AddText(IFileDialogCustomize *iface, DWORD id, LPCWSTR text) {
    Dlg *d = from_customize(iface);
    HRESULT hr = IFileDialogCustomize_AddText(REAL(d), id, text);
    if (SUCCEEDED(hr)) add_control(d, id, TEXT, text, FALSE);
    return hr;
}
static HRESULT WINAPI cus_StartVisualGroup(IFileDialogCustomize *iface, DWORD id, LPCWSTR label) {
    Dlg *d = from_customize(iface);
    HRESULT hr = IFileDialogCustomize_StartVisualGroup(REAL(d), id, label);
    if (SUCCEEDED(hr)) add_control(d, id, GROUP, label, FALSE);
    return hr;
}
static HRESULT WINAPI cus_EndVisualGroup(IFileDialogCustomize *iface) {
    return IFileDialogCustomize_EndVisualGroup(REAL(from_customize(iface)));
}
static HRESULT WINAPI cus_MakeProminent(IFileDialogCustomize *iface, DWORD id) {
    return IFileDialogCustomize_MakeProminent(REAL(from_customize(iface)), id);
}

static HRESULT WINAPI cus_SetControlLabel(IFileDialogCustomize *iface, DWORD id, LPCWSTR label) {
    Dlg *d = from_customize(iface);
    Control *c = control(d, id);
    if (c) {
        replace(&c->label, label ? label : L"");
        HWND hwnd = control_window(d, c);
        if (hwnd && c->kind != SEPARATOR) SetWindowTextW(hwnd, c->label);
    }
    return IFileDialogCustomize_SetControlLabel(REAL(d), id, label);
}

static void show_state(Dlg *d, Control *c) {
    HWND hwnd = control_window(d, c);
    if (!hwnd) return;
    EnableWindow(hwnd, (c->state & CDCS_ENABLED) != 0);
    ShowWindow(hwnd, (c->state & CDCS_VISIBLE) ? SW_SHOWNA : SW_HIDE);
}

static HRESULT WINAPI cus_GetControlState(IFileDialogCustomize *iface, DWORD id, CDCONTROLSTATEF *state) {
    Dlg *d = from_customize(iface);
    Control *c = control(d, id);
    if (c && state) {
        *state = c->state;
        return S_OK;
    }
    return IFileDialogCustomize_GetControlState(REAL(d), id, state);
}
static HRESULT WINAPI cus_SetControlState(IFileDialogCustomize *iface, DWORD id, CDCONTROLSTATEF state) {
    Dlg *d = from_customize(iface);
    Control *c = control(d, id);
    if (c) {
        c->state = state;
        show_state(d, c);
    }
    return IFileDialogCustomize_SetControlState(REAL(d), id, state);
}

static HRESULT WINAPI cus_GetCheckButtonState(IFileDialogCustomize *iface, DWORD id, BOOL *checked) {
    Dlg *d = from_customize(iface);
    Control *c = control(d, id);
    if (c && c->kind == CHECK && checked && !d->wineOnly) {
        *checked = c->checked;
        return S_OK;
    }
    return IFileDialogCustomize_GetCheckButtonState(REAL(d), id, checked);
}
static HRESULT WINAPI cus_SetCheckButtonState(IFileDialogCustomize *iface, DWORD id, BOOL checked) {
    Dlg *d = from_customize(iface);
    Control *c = control(d, id);
    if (c && c->kind == CHECK) {
        c->checked = checked;
        HWND hwnd = control_window(d, c);
        if (hwnd) SendMessageW(hwnd, BM_SETCHECK, checked ? BST_CHECKED : BST_UNCHECKED, 0);
    }
    return IFileDialogCustomize_SetCheckButtonState(REAL(d), id, checked);
}

static HRESULT WINAPI cus_GetEditBoxText(IFileDialogCustomize *iface, DWORD id, WCHAR **text) {
    return IFileDialogCustomize_GetEditBoxText(REAL(from_customize(iface)), id, text);
}
static HRESULT WINAPI cus_SetEditBoxText(IFileDialogCustomize *iface, DWORD id, LPCWSTR text) {
    return IFileDialogCustomize_SetEditBoxText(REAL(from_customize(iface)), id, text);
}
static HRESULT WINAPI cus_AddControlItem(IFileDialogCustomize *iface, DWORD id, DWORD item, LPCWSTR label) {
    return IFileDialogCustomize_AddControlItem(REAL(from_customize(iface)), id, item, label);
}
static HRESULT WINAPI cus_RemoveControlItem(IFileDialogCustomize *iface, DWORD id, DWORD item) {
    return IFileDialogCustomize_RemoveControlItem(REAL(from_customize(iface)), id, item);
}
static HRESULT WINAPI cus_RemoveAllControlItems(IFileDialogCustomize *iface, DWORD id) {
    return IFileDialogCustomize_RemoveAllControlItems(REAL(from_customize(iface)), id);
}
static HRESULT WINAPI cus_GetControlItemState(IFileDialogCustomize *iface, DWORD id, DWORD item, CDCONTROLSTATEF *state) {
    return IFileDialogCustomize_GetControlItemState(REAL(from_customize(iface)), id, item, state);
}
static HRESULT WINAPI cus_SetControlItemState(IFileDialogCustomize *iface, DWORD id, DWORD item, CDCONTROLSTATEF state) {
    return IFileDialogCustomize_SetControlItemState(REAL(from_customize(iface)), id, item, state);
}
static HRESULT WINAPI cus_GetSelectedControlItem(IFileDialogCustomize *iface, DWORD id, DWORD *item) {
    return IFileDialogCustomize_GetSelectedControlItem(REAL(from_customize(iface)), id, item);
}
static HRESULT WINAPI cus_SetSelectedControlItem(IFileDialogCustomize *iface, DWORD id, DWORD item) {
    return IFileDialogCustomize_SetSelectedControlItem(REAL(from_customize(iface)), id, item);
}

typedef HRESULT (WINAPI *SetControlItemTextFn)(IFileDialogCustomize *, DWORD, DWORD, LPCWSTR);
static HRESULT WINAPI cus_SetControlItemText(IFileDialogCustomize *iface, DWORD id, DWORD item, LPCWSTR label) {
    IFileDialogCustomize *real = REAL(from_customize(iface));
    SetControlItemTextFn next = (SetControlItemTextFn)((void **)real->lpVtbl)[sizeof(IFileDialogCustomizeVtbl) / sizeof(void *)];
    return next(real, id, item, label);
}

static const struct {
    IFileDialogCustomizeVtbl base;
    SetControlItemTextFn SetControlItemText;
} customizeVtbl = {
    {
        cus_QueryInterface, cus_AddRef, cus_Release, cus_EnableOpenDropDown, cus_AddMenu, cus_AddPushButton,
        cus_AddComboBox, cus_AddRadioButtonList, cus_AddCheckButton, cus_AddEditBox, cus_AddSeparator, cus_AddText,
        cus_SetControlLabel, cus_GetControlState, cus_SetControlState, cus_GetEditBoxText, cus_SetEditBoxText,
        cus_GetCheckButtonState, cus_SetCheckButtonState, cus_AddControlItem, cus_RemoveControlItem,
        cus_RemoveAllControlItems, cus_GetControlItemState, cus_SetControlItemState, cus_GetSelectedControlItem,
        cus_SetSelectedControlItem, cus_StartVisualGroup, cus_EndVisualGroup, cus_MakeProminent,
    },
    cus_SetControlItemText,
};

typedef HRESULT (WINAPI *EventFn)(IFileDialogEvents *, IFileDialog *);

static void tell(Dlg *d, size_t slot, const char *what) {
    IFileDialogEvents *sinks[MAX_SINKS];
    int count = d->sinkCount;
    for (int i = 0; i < count; i++) IFileDialogEvents_AddRef(sinks[i] = d->sinks[i].sink);
    for (int i = 0; i < count; i++) {
        EventFn fn = (EventFn)((void **)sinks[i]->lpVtbl)[slot];
        fn(sinks[i], &d->dialog);
        IFileDialogEvents_Release(sinks[i]);
    }
    if (count) note("told %d handler(s): %s", count, what);
}

#define EVENT_SLOT(name) (offsetof(IFileDialogEventsVtbl, name) / sizeof(void *))

static void take_results(Dlg *d, const OPENFILENAMEW *ofn) {
    clear_results(d);
    const WCHAR *file = ofn->lpstrFile;
    BOOL several = ofn->nFileOffset > 0 && !file[ofn->nFileOffset - 1];
    UINT count = 0;
    if (several)
        for (const WCHAR *p = file + ofn->nFileOffset; *p; p += wcslen(p) + 1) count++;
    else if (file[0])
        count = 1;
    if (!count || !(d->results = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, count * sizeof *d->results))) return;
    if (!several) {
        if ((d->results[0] = copy(file))) d->resultCount = 1;
        return;
    }
    for (const WCHAR *p = file + ofn->nFileOffset; *p && d->resultCount < count; p += wcslen(p) + 1) {
        size_t length = wcslen(file) + 1 + wcslen(p) + 1;
        WCHAR *path = HeapAlloc(GetProcessHeap(), 0, length * sizeof(WCHAR));
        if (!path) break;
        BOOL slash = file[0] && file[wcslen(file) - 1] == L'\\';
        _snwprintf(path, length, slash ? L"%ls%ls" : L"%ls\\%ls", file, p);
        path[length - 1] = 0;
        d->results[d->resultCount++] = path;
    }
}

static void place_controls(Dlg *d) {
    HWND name = GetDlgItem(d->hwnd, cmb13);
    if (!name) name = GetDlgItem(d->hwnd, edt1);
    if (!name) return;
    RECT box;
    GetWindowRect(name, &box);
    MapWindowPoints(NULL, d->child, (POINT *)&box, 2);
    for (int i = 0; i < d->controlCount; i++) {
        HWND hwnd = control_window(d, &d->controls[i]);
        if (!hwnd) continue;
        RECT rect;
        GetWindowRect(hwnd, &rect);
        MapWindowPoints(NULL, d->child, (POINT *)&rect, 2);
        SetWindowPos(hwnd, NULL, box.left, rect.top, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
}

static UINT_PTR CALLBACK hook(HWND child, UINT message, WPARAM wparam, LPARAM lparam) {
    Dlg *d = (Dlg *)GetWindowLongPtrW(child, DWLP_USER);
    if (message == WM_INITDIALOG) {
        d = (Dlg *)((OPENFILENAMEW *)lparam)->lCustData;
        SetWindowLongPtrW(child, DWLP_USER, (LONG_PTR)d);
        d->child = child;
        d->hwnd = GetParent(child);
        for (int i = 0; i < d->controlCount; i++) {
            Control *c = &d->controls[i];
            if (c->kind == CHECK) SendMessageW(control_window(d, c), BM_SETCHECK, c->checked ? BST_CHECKED : BST_UNCHECKED, 0);
            show_state(d, c);
        }
        return TRUE;
    }
    if (!d) return FALSE;

    if (message == WM_COMMAND && HIWORD(wparam) == BN_CLICKED) {
        int index = (int)LOWORD(wparam) - FIRST_CONTROL_ID;
        if (index < 0 || index >= d->controlCount || d->controls[index].kind != CHECK) return FALSE;
        Control *c = &d->controls[index];
        c->checked = SendMessageW((HWND)lparam, BM_GETCHECK, 0, 0) == BST_CHECKED;
        IFileDialogCustomize_SetCheckButtonState(REAL(d), c->id, c->checked);
        IFileDialogEvents *sinks[MAX_SINKS];
        int count = d->sinkCount;
        for (int i = 0; i < count; i++) IFileDialogEvents_AddRef(sinks[i] = d->sinks[i].sink);
        for (int i = 0; i < count; i++) {
            IFileDialogControlEvents *events = NULL;
            if (SUCCEEDED(IFileDialogEvents_QueryInterface(sinks[i], &IID_IFileDialogControlEvents, (void **)&events))) {
                IFileDialogControlEvents_OnCheckButtonToggled(events, &d->customize, c->id, c->checked);
                IFileDialogControlEvents_Release(events);
            }
            IFileDialogEvents_Release(sinks[i]);
        }
        return TRUE;
    }

    if (message != WM_NOTIFY) return FALSE;
    OFNOTIFYW *notify = (OFNOTIFYW *)lparam;
    switch (notify->hdr.code) {
    case CDN_INITDONE:
        if (d->okLabel) SendMessageW(d->hwnd, CDM_SETCONTROLTEXT, IDOK, (LPARAM)d->okLabel);
        if (d->nameLabel) SendMessageW(d->hwnd, CDM_SETCONTROLTEXT, stc3, (LPARAM)d->nameLabel);
        place_controls(d);
        break;
    case CDN_FOLDERCHANGE:
        tell(d, EVENT_SLOT(OnFolderChange), "folder changed");
        break;
    case CDN_SELCHANGE:
        tell(d, EVENT_SLOT(OnSelectionChange), "selection changed");
        break;
    case CDN_TYPECHANGE:
        IFileDialog_SetFileTypeIndex(d->real, notify->lpOFN->nFilterIndex);
        tell(d, EVENT_SLOT(OnTypeChange), "file type changed");
        break;
    case CDN_FILEOK: {
        take_results(d, notify->lpOFN);
        IFileDialog_SetFileTypeIndex(d->real, notify->lpOFN->nFilterIndex);
        IFileDialogEvents *sinks[MAX_SINKS];
        int count = d->sinkCount;
        BOOL keepOpen = FALSE;
        for (int i = 0; i < count; i++) IFileDialogEvents_AddRef(sinks[i] = d->sinks[i].sink);
        for (int i = 0; i < count; i++) {
            if (!keepOpen && IFileDialogEvents_OnFileOk(sinks[i], &d->dialog) != S_OK) keepOpen = TRUE;
            IFileDialogEvents_Release(sinks[i]);
        }
        note("OK: %s%s", d->resultCount ? narrow(d->results[0]) : "(nothing)", keepOpen ? ", the program kept the dialog open" : "");
        if (keepOpen) {
            clear_results(d);
            SetWindowLongPtrW(child, DWLP_MSGRESULT, 1);
            return TRUE;
        }
        break;
    }
    }
    return FALSE;
}

static void *controls_template(Dlg *d) {
    size_t size = sizeof(DLGTEMPLATE) + 64;
    for (int i = 0; i < d->controlCount; i++) size += sizeof(DLGITEMTEMPLATE) + (wcslen(d->controls[i].label) + 8) * sizeof(WCHAR) + 8;
    BYTE *memory = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size);
    if (!memory) return NULL;
    DLGTEMPLATE *dialog = (DLGTEMPLATE *)memory;
    const int row = 12, width = 220;
    dialog->style = WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | DS_CONTROL | DS_3DLOOK | DS_SETFONT;
    dialog->cdit = (WORD)d->controlCount;
    dialog->cx = width + 8;
    dialog->cy = (short)(d->controlCount * row + 4);
    WORD *p = (WORD *)(dialog + 1);
    *p++ = 0;
    *p++ = 0;
    *p++ = 0;
    *p++ = 8;
    wcscpy((WCHAR *)p, L"MS Shell Dlg");
    p += wcslen(L"MS Shell Dlg") + 1;
    for (int i = 0; i < d->controlCount; i++) {
        Control *c = &d->controls[i];
        p = (WORD *)(((ULONG_PTR)p + 3) & ~(ULONG_PTR)3);
        DLGITEMTEMPLATE *item = (DLGITEMTEMPLATE *)p;
        item->x = 4;
        item->y = (short)(2 + i * row);
        item->cx = width;
        item->cy = c->kind == SEPARATOR ? 1 : 10;
        item->id = (WORD)(FIRST_CONTROL_ID + i);
        item->style = WS_CHILD | WS_VISIBLE |
                      (c->kind == CHECK ? BS_AUTOCHECKBOX | WS_TABSTOP : c->kind == SEPARATOR ? SS_ETCHEDHORZ : SS_LEFT);
        p = (WORD *)(item + 1);
        *p++ = 0xFFFF;
        *p++ = c->kind == CHECK ? 0x0080 : 0x0082;
        const WCHAR *label = c->kind == SEPARATOR ? L"" : c->label;
        wcscpy((WCHAR *)p, label);
        p += wcslen(label) + 1;
        *p++ = 0;
    }
    return memory;
}

static DWORD ofn_flags(FILEOPENDIALOGOPTIONS options) {
    static const struct { FILEOPENDIALOGOPTIONS fos; DWORD ofn; } map[] = {
        {FOS_OVERWRITEPROMPT, OFN_OVERWRITEPROMPT}, {FOS_ALLOWMULTISELECT, OFN_ALLOWMULTISELECT},
        {FOS_PATHMUSTEXIST, OFN_PATHMUSTEXIST},     {FOS_FILEMUSTEXIST, OFN_FILEMUSTEXIST},
        {FOS_CREATEPROMPT, OFN_CREATEPROMPT},       {FOS_SHAREAWARE, OFN_SHAREAWARE},
        {FOS_NOREADONLYRETURN, OFN_NOREADONLYRETURN}, {FOS_NOTESTFILECREATE, OFN_NOTESTFILECREATE},
        {FOS_NODEREFERENCELINKS, OFN_NODEREFERENCELINKS}, {FOS_DONTADDTORECENT, OFN_DONTADDTORECENT},
        {FOS_FORCESHOWHIDDEN, OFN_FORCESHOWHIDDEN}, {FOS_NOVALIDATE, OFN_NOVALIDATE},
    };
    DWORD flags = OFN_EXPLORER | OFN_ENABLEHOOK | OFN_ENABLESIZING | OFN_HIDEREADONLY | OFN_NOCHANGEDIR;
    for (size_t i = 0; i < sizeof map / sizeof *map; i++)
        if (options & map[i].fos) flags |= map[i].ofn;
    return flags;
}

static HRESULT show_explorer_dialog(Dlg *d, HWND owner) {
    FILEOPENDIALOGOPTIONS options = 0;
    UINT typeIndex = 0;
    WCHAR *name = NULL;
    IFileDialog_GetOptions(d->real, &options);
    IFileDialog_GetFileTypeIndex(d->real, &typeIndex);
    IFileDialog_GetFileName(d->real, &name);

    WCHAR *file = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, FILE_BUFFER * sizeof(WCHAR));
    if (!file) {
        CoTaskMemFree(name);
        return E_OUTOFMEMORY;
    }
    WCHAR *saveAsPath = item_path(d->saveAs);
    if (name && name[0]) lstrcpynW(file, name, FILE_BUFFER);
    else if (saveAsPath) lstrcpynW(file, PathFindFileNameW(saveAsPath), FILE_BUFFER);
    CoTaskMemFree(name);

    WCHAR start[MAX_PATH] = {0};
    WCHAR *folder = item_path(d->folder);
    if (!folder) folder = item_path(d->defaultFolder);
    if (folder) lstrcpynW(start, folder, MAX_PATH);
    else if (saveAsPath) {
        lstrcpynW(start, saveAsPath, MAX_PATH);
        PathRemoveFileSpecW(start);
    } else downloads_folder(start, MAX_PATH);
    CoTaskMemFree(folder);
    CoTaskMemFree(saveAsPath);

    void *controls = d->controlCount ? controls_template(d) : NULL;
    OPENFILENAMEW ofn = {sizeof ofn};
    ofn.hwndOwner = owner;
    ofn.lpstrFilter = d->filter;
    ofn.nFilterIndex = d->filter ? (typeIndex ? typeIndex : 1) : 0;
    ofn.lpstrFile = file;
    ofn.nMaxFile = FILE_BUFFER;
    ofn.lpstrInitialDir = start[0] ? start : NULL;
    ofn.lpstrTitle = d->title;
    ofn.lpstrDefExt = d->defaultExtension && d->defaultExtension[0] == L'.' ? d->defaultExtension + 1 : d->defaultExtension;
    ofn.Flags = ofn_flags(options) | (controls ? OFN_ENABLETEMPLATEHANDLE : 0);
    ofn.hInstance = (HINSTANCE)controls;
    ofn.lCustData = (LPARAM)d;
    ofn.lpfnHook = hook;

    note("Show: Explorer-style %s dialog in %s, %d added control(s)", d->save ? "save" : "open", narrow(ofn.lpstrInitialDir),
         d->controlCount);
    clear_results(d);
    d->closed = FALSE;
    d->ofn = &ofn;
    IFileDialog_AddRef(&d->dialog);
    BOOL picked = d->save ? GetSaveFileNameW(&ofn) : GetOpenFileNameW(&ofn);
    DWORD error = picked ? 0 : CommDlgExtendedError();
    d->hwnd = d->child = NULL;
    d->ofn = NULL;
    if (controls) HeapFree(GetProcessHeap(), 0, controls);

    HRESULT hr;
    if (picked) {
        take_results(d, &ofn);
        IFileDialog_SetFileTypeIndex(d->real, ofn.nFilterIndex);
        if (d->resultCount == 1) {
            IFileDialog_SetFileName(d->real, PathFindFileNameW(d->results[0]));
            WCHAR there[MAX_PATH];
            lstrcpynW(there, d->results[0], MAX_PATH);
            PathRemoveFileSpecW(there);
            IShellItem *item = NULL;
            if (SUCCEEDED(path_item(there, &IID_IShellItem, (void **)&item))) {
                IFileDialog_SetFolder(d->real, item);
                IShellItem_Release(item);
            }
        }
        note("picked %u: %s", d->resultCount, d->resultCount ? narrow(d->results[0]) : "");
        hr = d->resultCount ? S_OK : E_FAIL;
    } else if (d->closed) {
        hr = d->closeResult;
    } else if (error) {
        note("the Explorer-style dialog failed (0x%lx); Wine's item dialog instead", error);
        hr = IFileDialog_Show(d->real, owner);
    } else {
        note("dismissed");
        hr = HRESULT_FROM_WIN32(ERROR_CANCELLED);
    }
    HeapFree(GetProcessHeap(), 0, file);
    IFileDialog_Release(&d->dialog);
    return hr;
}

typedef HRESULT (WINAPI *GetClassObjectFn)(REFCLSID, REFIID, void **);

static HRESULT wine_class(REFCLSID clsid, REFIID riid, void **out) {
    HMODULE comdlg = LoadLibraryW(L"comdlg32.dll");
    GetClassObjectFn get = comdlg ? (GetClassObjectFn)(void *)GetProcAddress(comdlg, "DllGetClassObject") : NULL;
    return get ? get(clsid, riid, out) : CLASS_E_CLASSNOTAVAILABLE;
}

typedef struct {
    IClassFactory factory;
    BOOL save;
} Factory;

static HRESULT WINAPI factory_QueryInterface(IClassFactory *iface, REFIID riid, void **out) {
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IClassFactory)) {
        *out = iface;
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}
static ULONG WINAPI factory_AddRef(IClassFactory *iface) { return 2; }
static ULONG WINAPI factory_Release(IClassFactory *iface) { return 1; }

static HRESULT WINAPI factory_CreateInstance(IClassFactory *iface, IUnknown *outer, REFIID riid, void **out) {
    Factory *f = CONTAINING_RECORD(iface, Factory, factory);
    *out = NULL;
    if (outer) return CLASS_E_NOAGGREGATION;
    IClassFactory *wine = NULL;
    HRESULT hr = wine_class(f->save ? &CLSID_FerryFileSaveDialog : &CLSID_FerryFileOpenDialog, &IID_IClassFactory, (void **)&wine);
    if (FAILED(hr)) return hr;
    Dlg *d = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof *d);
    if (!d) {
        IClassFactory_Release(wine);
        return E_OUTOFMEMORY;
    }
    hr = IClassFactory_CreateInstance(wine, NULL, f->save ? &IID_IFileSaveDialog : &IID_IFileOpenDialog, (void **)&d->real);
    IClassFactory_Release(wine);
    if (FAILED(hr)) {
        HeapFree(GetProcessHeap(), 0, d);
        return hr;
    }
    d->dialog.lpVtbl = f->save ? (IFileDialogVtbl *)&saveVtbl : (IFileDialogVtbl *)&openVtbl;
    d->customize.lpVtbl = (IFileDialogCustomizeVtbl *)&customizeVtbl;
    d->window.lpVtbl = (IOleWindowVtbl *)&windowVtbl;
    d->refs = 1;
    d->save = f->save;
    hr = dlg_QueryInterface(&d->dialog, riid, out);
    dlg_Release(&d->dialog);
    note("new %s dialog", f->save ? "save" : "open");
    return hr;
}

static HRESULT WINAPI factory_LockServer(IClassFactory *iface, BOOL lock) { return S_OK; }

static const IClassFactoryVtbl factoryVtbl = {
    factory_QueryInterface, factory_AddRef, factory_Release, factory_CreateInstance, factory_LockServer,
};
static Factory openFactory = {{(IClassFactoryVtbl *)&factoryVtbl}, FALSE}, saveFactory = {{(IClassFactoryVtbl *)&factoryVtbl}, TRUE};

static BOOL switched_off(void) {
    char value[8];
    DWORD n = GetEnvironmentVariableA("FERRY_FILEDLG", value, sizeof value);
    return n && n < sizeof value && !lstrcmpiA(value, "off");
}

HRESULT WINAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void **out) {
    *out = NULL;
    BOOL save = IsEqualCLSID(clsid, &CLSID_FerryFileSaveDialog);
    if (!save && !IsEqualCLSID(clsid, &CLSID_FerryFileOpenDialog)) return CLASS_E_CLASSNOTAVAILABLE;
    if (switched_off()) return wine_class(clsid, riid, out);
    return factory_QueryInterface(&(save ? &saveFactory : &openFactory)->factory, riid, out);
}

HRESULT WINAPI DllCanUnloadNow(void) { return S_FALSE; }

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, void *reserved) {
    if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(instance);
    return TRUE;
}
