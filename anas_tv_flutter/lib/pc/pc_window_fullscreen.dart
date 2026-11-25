import 'dart:ffi';
import 'dart:io';
import 'pc_trace_log.dart';

final class _Point extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final class _WindowPlacement extends Struct {
  @Uint32()
  external int length;
  @Uint32()
  external int flags;
  @Uint32()
  external int showCmd;
  external _Point ptMinPosition;
  external _Point ptMaxPosition;
  external _Rect rcNormalPosition;
}

final class _MonitorInfo extends Struct {
  @Uint32()
  external int cbSize;
  external _Rect rcMonitor;
  external _Rect rcWork;
  @Uint32()
  external int dwFlags;
}

class PcWindowFullscreen {
  PcWindowFullscreen._();

  static const int _gwlStyle = -16;
  static const int _gwlExStyle = -20;
  static const int _wsOverlappedWindow = 0x00CF0000;
  static const int _wsExBorders = 0x00020301;
  static const int _monitorDefaultToNearest = 2;
  static const int _gaRoot = 2;
  static const int _swpNoSize = 0x0001;
  static const int _swpNoMove = 0x0002;
  static const int _swpNoZOrder = 0x0004;
  static const int _swpFrameChanged = 0x0020;
  static const int _swpShowWindow = 0x0040;
  static const int _swpNoOwnerZOrder = 0x0200;

  static DynamicLibrary? _user32;
  static DynamicLibrary? _kernel32;
  static bool _isFullscreen = false;
  static int _savedStyle = 0;
  static int _savedExStyle = 0;
  static Pointer<_WindowPlacement>? _savedPlacement;

  static bool get isFullscreen => _isFullscreen;

  static void _ensureLibs() {
    _user32 ??= DynamicLibrary.open('user32.dll');
    _kernel32 ??= DynamicLibrary.open('kernel32.dll');
  }

  static Pointer<Void> _allocZero(int bytes) {
    final k32 = _kernel32!;
    final getHeap = k32.lookupFunction<IntPtr Function(), int Function()>('GetProcessHeap');
    final heapAlloc = k32.lookupFunction<
        Pointer<Void> Function(IntPtr, Uint32, IntPtr),
        Pointer<Void> Function(int, int, int)>('HeapAlloc');
    return heapAlloc(getHeap(), 0x00000008, bytes);
  }

  static void _free(Pointer<Void> ptr) {
    if (ptr == nullptr) return;
    final k32 = _kernel32!;
    final getHeap = k32.lookupFunction<IntPtr Function(), int Function()>('GetProcessHeap');
    final heapFree = k32.lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Void>),
        int Function(int, int, Pointer<Void>)>('HeapFree');
    heapFree(getHeap(), 0, ptr);
  }

  static Pointer<Uint16> _toUtf16(String s) {
    final units = s.codeUnits;
    final ptr = _allocZero((units.length + 1) * 2).cast<Uint16>();
    for (var i = 0; i < units.length; i++) {
      ptr[i] = units[i];
    }
    ptr[units.length] = 0;
    return ptr;
  }

  static int _findOwnHwnd() {
    final u32 = _user32!;
    final k32 = _kernel32!;

    final getCurrentPid = k32.lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');
    final currentPid = getCurrentPid();

    final getWinPid = u32.lookupFunction<
        Uint32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
    final findWindowW = u32.lookupFunction<
        IntPtr Function(Pointer<Uint16>, Pointer<Uint16>),
        int Function(Pointer<Uint16>, Pointer<Uint16>)>('FindWindowW');
    final getForegroundWindow = u32.lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');
    final getActiveWindow = u32.lookupFunction<IntPtr Function(), int Function()>('GetActiveWindow');
    final getAncestor = u32.lookupFunction<
        IntPtr Function(IntPtr, Uint32),
        int Function(int, int)>('GetAncestor');

    bool belongsToUs(int hwnd) {
      if (hwnd == 0) return false;
      final pidBuf = _allocZero(4).cast<Uint32>();
      try {
        getWinPid(hwnd, pidBuf);
        return pidBuf.value == currentPid;
      } finally {
        _free(pidBuf.cast<Void>());
      }
    }

    final active = getActiveWindow();
    if (active != 0) {
      final root = getAncestor(active, _gaRoot);
      if (belongsToUs(root != 0 ? root : active)) {
        return root != 0 ? root : active;
      }
    }

    final fg = getForegroundWindow();
    if (fg != 0) {
      final root = getAncestor(fg, _gaRoot);
      if (belongsToUs(root != 0 ? root : fg)) {
        return root != 0 ? root : fg;
      }
    }

    final clsPtr = _toUtf16('FLUTTER_RUNNER_WIN32_WINDOW');
    final titlePtr = _toUtf16('AnasTV');
    try {
      final hwndByTitle = findWindowW(clsPtr, titlePtr);
      if (belongsToUs(hwndByTitle)) return hwndByTitle;
      final hwndByClass = findWindowW(clsPtr, nullptr);
      if (belongsToUs(hwndByClass)) return hwndByClass;
    } finally {
      _free(clsPtr.cast<Void>());
      _free(titlePtr.cast<Void>());
    }
    return 0;
  }

  static bool setFullscreen(bool enable) {
    if (!Platform.isWindows) return false;
    if (_isFullscreen == enable) return _isFullscreen;

    try {
      _ensureLibs();
      final hwnd = _findOwnHwnd();
      if (hwnd == 0) {
        PcTraceLog.write('window: fullscreen($enable) skipped, HWND=0');
        return _isFullscreen;
      }

      final u32 = _user32!;
      final getLongPtr = u32.lookupFunction<
          IntPtr Function(IntPtr, Int32),
          int Function(int, int)>('GetWindowLongPtrW');
      final setLongPtr = u32.lookupFunction<
          IntPtr Function(IntPtr, Int32, IntPtr),
          int Function(int, int, int)>('SetWindowLongPtrW');
      final getPlacement = u32.lookupFunction<
          Int32 Function(IntPtr, Pointer<_WindowPlacement>),
          int Function(int, Pointer<_WindowPlacement>)>('GetWindowPlacement');
      final setPlacement = u32.lookupFunction<
          Int32 Function(IntPtr, Pointer<_WindowPlacement>),
          int Function(int, Pointer<_WindowPlacement>)>('SetWindowPlacement');
      final monitorFromWindow = u32.lookupFunction<
          IntPtr Function(IntPtr, Uint32),
          int Function(int, int)>('MonitorFromWindow');
      final getMonitorInfo = u32.lookupFunction<
          Int32 Function(IntPtr, Pointer<_MonitorInfo>),
          int Function(int, Pointer<_MonitorInfo>)>('GetMonitorInfoW');
      final setWindowPos = u32.lookupFunction<
          Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
          int Function(int, int, int, int, int, int, int)>('SetWindowPos');

      if (enable) {
        _savedStyle = getLongPtr(hwnd, _gwlStyle);
        _savedExStyle = getLongPtr(hwnd, _gwlExStyle);
        _savedPlacement ??= _allocZero(sizeOf<_WindowPlacement>()).cast<_WindowPlacement>();
        _savedPlacement!.ref.length = sizeOf<_WindowPlacement>();
        getPlacement(hwnd, _savedPlacement!);

        final hMon = monitorFromWindow(hwnd, _monitorDefaultToNearest);
        final miPtr = _allocZero(sizeOf<_MonitorInfo>()).cast<_MonitorInfo>();
        try {
          miPtr.ref.cbSize = sizeOf<_MonitorInfo>();
          if (hMon != 0 && getMonitorInfo(hMon, miPtr) != 0) {
            final mon = miPtr.ref.rcMonitor;
            setLongPtr(hwnd, _gwlStyle, _savedStyle & ~_wsOverlappedWindow);
            setLongPtr(hwnd, _gwlExStyle, _savedExStyle & ~_wsExBorders);
            setWindowPos(
              hwnd,
              0,
              mon.left,
              mon.top,
              mon.right - mon.left,
              mon.bottom - mon.top,
              _swpNoOwnerZOrder | _swpFrameChanged | _swpShowWindow,
            );
            _isFullscreen = true;
          }
        } finally {
          _free(miPtr.cast<Void>());
        }
      } else {
        if (_savedStyle != 0) {
          setLongPtr(hwnd, _gwlStyle, _savedStyle);
        }
        setLongPtr(hwnd, _gwlExStyle, _savedExStyle);
        if (_savedPlacement != null) {
          setPlacement(hwnd, _savedPlacement!);
        }
        setWindowPos(
          hwnd,
          0,
          0,
          0,
          0,
          0,
          _swpNoMove | _swpNoSize | _swpNoZOrder | _swpNoOwnerZOrder | _swpFrameChanged | _swpShowWindow,
        );
        _isFullscreen = false;
      }
      PcTraceLog.write('window: fullscreen=$_isFullscreen hwnd=$hwnd');
    } catch (e, st) {
      PcTraceLog.write('window: setFullscreen($enable) failed: $e\n$st');
    }
    return _isFullscreen;
  }

  static bool toggle() => setFullscreen(!_isFullscreen);
}
