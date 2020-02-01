package ammer;

import haxe.macro.Expr;

typedef AmmerMethodPatchContext = {
  top:AmmerContext,
  name:String,
  native:String,
  isMacro:Bool,
  ffiArgs:Array<FFIType>,
  ffiRet:FFIType,
  field:Field,
  fn:Function,
  callArgs:Array<Expr>,
  callExpr:Expr,
  wrapArgs:Array<FunctionArg>,
  wrapExpr:Expr,
  externArgs:Array<FunctionArg>
};
