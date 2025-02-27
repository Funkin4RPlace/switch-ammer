package ammer.patch;

import haxe.macro.Expr;

class PatchCpp {
  public static function patch(ctx:AmmerContext):Void {
    var pos = ctx.implType.pos;
    ctx.externIsExtern = false;
    var headerCode = '#include "../ammer/ammer_${ctx.libraryConfig.name}.cpp.${ctx.libraryConfig.abi == Cpp ? "cpp" : "c"}"';
    ctx.externMeta.push({
      name: ":headerCode",
      params: [{expr: EConst(CString(headerCode)), pos: ctx.implType.pos}],
      pos: pos
    });
    var cppFileCode = '#define AMMER_CODE_${ctx.index}
#include "../ammer/ammer_${ctx.libraryConfig.name}.cpp.${ctx.libraryConfig.abi == Cpp ? "cpp" : "c"}"
#undef AMMER_CODE_${ctx.index}';
    ctx.externMeta.push({
      name: ":cppFileCode",
      params: [{expr: EConst(CString(cppFileCode)), pos: ctx.implType.pos}],
      pos: pos
    });
    var lb = new LineBuf();
    lb.ai('<files id="haxe">\n');
    lb.indent(() -> {
      for (path in ctx.libraryConfig.includePath)
        lb.ai('<compilerflag value="-I$path"/>\n');
    });
    lb.ai('</files>\n');
    lb.ai('<target id="haxe">\n');
    #if !libnx
    lb.indent(() -> {
      for (path in ctx.libraryConfig.libraryPath)
        lb.ai('<libpath name="$path"/>\n');
      for (name in ctx.libraryConfig.linkName) {
        lb.ai('<lib name="-l$name" unless="windows" />\n');
        lb.ai('<lib name="$name" if="windows" />\n');
      }
    });
    #end
    lb.ai('</target>\n');
    ctx.externMeta.push({
      name: ":buildXml",
      params: [{expr: EConst(CString(lb.dump())), pos: pos}],
      pos: pos
    });
    for (t in FFITools.CONSTANT_TYPES) {
      if (!ctx.ffiConstants.exists(t.ffi))
        continue;
      var hxType = t.haxe;
      if (t.ffi == String)
        hxType = (macro : cpp.ConstPointer<cpp.Char>);
      ctx.externFields.push({
        access: [AStatic],
        name: 'ammer_g_${t.name}',
        kind: FFun({
          args: [],
          expr: {
            var vars = [ for (constant in ctx.ffiConstants[t.ffi]) {
              macro untyped __cpp__($v{'${constant.native}'});
            } ];
            macro return $a{vars};
          },
          ret: (macro : Array<$hxType>)
        }),
        pos: pos
      });
    }
  }

  public static function patchType(ctx:AmmerTypeContext):Void {
    var headerCode = '#include "../ammer/ammer_${ctx.libraryCtx.libraryConfig.name}.cpp.${ctx.libraryCtx.libraryConfig.abi == Cpp ? "cpp" : "c"}"';
    ctx.implType.meta.add(
      ":headerCode",
      [{expr: EConst(CString(headerCode)), pos: ctx.implType.pos}],
      ctx.implType.pos
    );
  }
}

class PatchCppMethod extends ammer.patch.PatchMethod {
  override public function visitArgument(i:Int, ffi:FFIType):Void {
    switch (ffi) {
      case NoSize(t):
        return visitArgument(i, t);
      case SizeOfReturn:
        ctx.callArgs[i] = macro cpp.Pointer.addressOf(($e{Utils.id("_retSize")} : cpp.Reference<cpp.SizeT>));
        ctx.wrapExpr = macro {
          var _retSize:cpp.SizeT = 0;
          ${ctx.wrapExpr};
        };
      case Bytes | WithSize(_, Bytes):
        externArgs.push({
          name: '_arg$i',
          type: (macro:cpp.Pointer<cpp.UInt8>)
        });
        return;
      case ClosureData(_):
        ctx.callArgs[i] = macro 0;
      case OutPointer(LibType(_, _)):
        ctx.callArgs[i] = macro untyped __cpp__("&{0}->ammerNative.ptr", $e{ctx.callArgs[i]});
      case Unsupported(_):
        ctx.callArgs[i] = macro 0;
      case _:
    }
    super.visitArgument(i, ffi);
  }

  override public function finish():Void {
    ctx.top.externFields.push({
      access: [APublic, AStatic, AExtern],
      name: ctx.ffi.uniqueName,
      kind: FFun({
        args: externArgs,
        expr: null,
        ret: mapType(ctx.ffi.ret)
      }),
      meta: [
        {
          name: ":native",
          params: [{expr: EConst(CString('::${ammer.stub.StubCpp.mapMethodName(ctx.ffi.uniqueName)}')), pos: ctx.ffi.field.pos}],
          pos: ctx.ffi.field.pos
        }
      ],
      pos: ctx.ffi.field.pos
    });
  }

  public static function mapType(t:FFIType):ComplexType {
    return (switch (t) {
      case Bytes: (macro:cpp.ConstPointer<cpp.Char>);
      case String: (macro:cpp.ConstPointer<cpp.Char>);
      case ArrayDynamic(idx, _) | WithSize(_, ArrayDynamic(idx, _)) | ArrayFixed(idx, _, _): Ammer.typeMap['ammer.externs.AmmerArray_$idx.AmmerArray_$idx'].nativeType;
      case SizeOfReturn: (macro:cpp.Pointer<cpp.SizeT>);
      case SizeOf(_): (macro:cpp.SizeT);
      case LibType(t, _) | Nested(LibType(t, _)) | Alloc(LibType(t, _)) | LibIntEnum(t, _): t.nativeType;
      case Derived(_, t) | WithSize(_, t) | NoSize(t) | SameSizeAs(t, _): mapType(t);
      case Closure(idx, args, ret, mode):
        TFunction(args.filter(a -> !a.match(ClosureDataUse)).map(mapType), mapType(ret));
      case _: t.toComplexType();
    });
  }
}
