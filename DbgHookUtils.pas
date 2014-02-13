unit DbgHookUtils;

interface

uses SysUtils, DbgHookTypes;

type
  TJclAddr = NativeInt;

  PStackFrame = ^TStackFrame;
  TStackFrame = record
    CallerFrame: TJclAddr;
    CallerAddr: TJclAddr;
  end;

procedure _Log(const Msg: AnsiString); overload;
procedure _Log(const Msg: String); overload;
procedure _LogException(E: Exception; const Code: Integer = 0);

function IsValidCodeAddr(const Addr: Pointer): Boolean;
function IsValidAddr(const Addr: Pointer): Boolean;

function _GetObjClassType(Obj: Pointer; var ObjClassName: ShortString): Boolean;

function GetFramePointer: Pointer; assembler;
function GetStackTop: TJclAddr; assembler;

procedure GetCallStack(var Stack: TDbgHookInfoStack; Level: Integer); stdcall;

implementation

uses Windows;

{ --- From JCL --- }
type
  NT_TIB32 = packed record
    ExceptionList: DWORD;
    StackBase: DWORD;
    StackLimit: DWORD;
    SubSystemTib: DWORD;
    case Integer of
      0 : (
        FiberData: DWORD;
        ArbitraryUserPointer: DWORD;
        Self: DWORD;
      );
      1 : (
        Version: DWORD;
      );
  end;
{ --- From JCL --- }

procedure _Log(const Msg: AnsiString);
begin
  OutputDebugStringA(PAnsiChar(Msg));
end;

procedure _Log(const Msg: String);
begin
  _Log(AnsiString(Msg));
end;

procedure _LogException(E: Exception; const Code: Integer = 0);
begin
  _Log(Format('DbgHook error (%d): %s', [Code, E.Message]));
end;

threadvar
  _Buf: TMemoryBasicInformation;

function IsValidCodeAddr(const Addr: Pointer): Boolean;
const
  _PAGE_CODE: Cardinal = (PAGE_EXECUTE Or PAGE_EXECUTE_READ or PAGE_EXECUTE_READWRITE Or PAGE_EXECUTE_WRITECOPY);
Begin
  Result := False;

  if (Addr = nil) or (Addr = Pointer(-1)) then Exit;

  Result := (VirtualQuery(Addr, _Buf, SizeOf(TMemoryBasicInformation)) <> 0) And ((_Buf.Protect And _PAGE_CODE) <> 0);
end;

function IsValidAddr(const Addr: Pointer): Boolean;
Begin
  Result := False;

  if (Addr = nil) or (Addr = Pointer(-1)) then Exit;

  Result := (VirtualQuery(Addr, _Buf, SizeOf(TMemoryBasicInformation)) <> 0);
end;

function _GetObjClassType(Obj: Pointer; var ObjClassName: ShortString): Boolean;
var
  ClassTypePtr: Pointer;
  ClassNamePtr: Pointer;
begin
  Result := False;
  try
    if not IsValidAddr(Obj) then Exit;

    ClassTypePtr := PPointer(Obj)^;
    if not IsValidCodeAddr(ClassTypePtr) then Exit;
    ClassNamePtr := Pointer(Integer(ClassTypePtr) + vmtClassName);
    if not IsValidCodeAddr(ClassNamePtr) then Exit;
    ClassNamePtr := PPointer(ClassNamePtr)^;
    if not IsValidCodeAddr(ClassNamePtr) then Exit;
    ObjClassName := PShortString(ClassNamePtr)^;
    Result := True;
  except
    on E: Exception do
      _LogException(E, _EHOOK_GetObjClassType);
  end;
end;

function GetFramePointer: Pointer; assembler;
asm
  MOV     EAX, EBP
end;

function GetStackTop: TJclAddr; assembler;
asm
  MOV     EAX, FS:[0].NT_TIB32.StackBase
end;

procedure GetCallStack(var Stack: TDbgHookInfoStack; Level: Integer); stdcall;
var
  TopOfStack: TJclAddr;
  BaseOfStack: TJclAddr;
  StackFrame: PStackFrame;
begin
  try
    ZeroMemory(@Stack[0], Length(Stack) * SizeOf(Pointer));

    StackFrame := GetFramePointer;
    BaseOfStack := TJclAddr(StackFrame) - 1;
    TopOfStack := GetStackTop;

    while (Level < Length(Stack)) and (
      (Level < 0) or (
        (BaseOfStack < TJclAddr(StackFrame)) and
        (TJclAddr(StackFrame) < TopOfStack) and
        IsValidAddr(StackFrame)
        // TODO: �� �����-�� ������� ��� �������� ������ �����
        // and IsValidCodeAddr(Pointer(StackFrame^.CallerAddr))
        )
      )
    do begin
      if Level >= 0 then
        Stack[Level] := Pointer(StackFrame^.CallerAddr - 1);

      StackFrame := PStackFrame(StackFrame^.CallerFrame);

      Inc(Level);
    end;
  except
    on E: Exception do
      _LogException(E, _EHOOK_GetCallStack);
  end;
end;

end.
