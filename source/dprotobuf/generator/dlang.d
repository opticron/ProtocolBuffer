/**
 * This module provides conversion functionality of different elements
 * to the D Programming Language.
 */
module dprotobuf.generator.dlang;

import dprotobuf.pbroot;
import dprotobuf.pbgeneral;
import dprotobuf.pbchild;
import dprotobuf.pbenum;
import dprotobuf.pbmessage;
import dprotobuf.wireformat;
import dprotobuf.generator.common;

version(D_Version2) {
	import std.algorithm;
	import std.range;
	import std.regex;
	mixin(`
	version(unittest) {
		PBMessage PBCompileTime(ParserData pbstring) {
			return PBMessage(pbstring);
		}
		PBEnum PBCTEnum(ParserData pbstring) {
			return PBEnum(pbstring);
		}
	}`);
}

import std.conv;
import std.string : format;

/*
 * Appropriately wraps the type based on the option.
 *
 * Repeated types are arrays.
 * All types are nullable
 */
private string typeWrapper(PBChild child) {
	if(child.modifier == "repeated")
		return format("Nullable!(%s[])", toDType(child.type));
	else
		return format("Nullable!(%s)", toDType(child.type));
}

string langD(PBRoot root) {
	auto code = CodeBuilder(0);
    code.put("import ProtocolBuffer.conversion.pbbinary;\n");
    code.put("import std.conv;\n");
    code.put("import std.typecons;\n\n");

    code.put("string makeString(T)(T v) {\n");
    code.put("\treturn to!string(v);\n");
    code.put("}\n");

    // do what we need for extensions defined here
    code.put(root.extensions.genExtString(""));
    // write out enums
    foreach(pbenum; root.enum_defs) {
        code.put(toD(pbenum, 0));
    }
    // write out message definitions
    foreach(pbmsg; root.message_defs) {
        code.put(toD(pbmsg, 0));
    }
    return code.finalize();
}

/**
 */
string toD(PBChild child, int indentCount = 0) {
	auto code = CodeBuilder(indentCount);
	with(child) {
		// Apply comments to field
		code.rawPut(addComments(comments, code.indentCount));

		// Make field declaration
		if(is_dep) code.put("deprecated ref ");
		else code.put("");
		code.rawPut(typeWrapper(child));
		code.rawPut(" ");
		code.rawPut(name);
		if(isReserved(name))
			code.rawPut("_");
		if(is_dep) {
			code.rawPut("() {\n", Indent.open);
			code.push("}\n");
			code.put("return " ~ name ~ "_dep;\n");
			code.pop();
			code.put("private ");
			code.rawPut(typeWrapper(child));
			code.put(" " ~ name ~ "_dep");
		}
		if(!empty(valdefault)) // Apply default value
			code.rawPut(" = " ~ valdefault);
		code.rawPut(";");
	}
	return code.finalize();
}

unittest {
	PBChild child;

	// Conversion for optional
	auto str = ParserData("optional HeaderBBox bbox = 1;");
	child = PBChild(str);
	string ans = "///\nNullable!(HeaderBBox) bbox;";
	assert(toD(child) == ans);

	// Conversion for repeated
	str = ParserData("repeated HeaderBBox bbox = 1;");
	child = PBChild(str);
	ans = "///\nNullable!(HeaderBBox[]) bbox;";
	assert(toD(child) == ans);

	// Conversion for required
	str = ParserData("required int32 value = 1;");
	child = PBChild(str);
	ans = "///\nNullable!(int) value;";
	assert(toD(child) == ans);

	// Conversion for default value
	str = ParserData("required int64 value = 1 [default=6]; ");
	child = PBChild(str);
	ans = "///\nNullable!(long) value = 6;";
	assert(toD(child) == ans);

	// Conversion for default, negative, deprecated value
	str = ParserData("optional int64 value = 1 [default=-32,deprecated=true];");
	child = PBChild(str);
	ans = "///\ndeprecated ref Nullable!(long) value() {\n";
	ans ~= "\treturn value_dep;\n}\n";
	ans ~= "private Nullable!(long) value_dep = -32;";
	assert(toD(child) == ans);

	// Conversion for commented, indented
	str = ParserData("optional HeaderBBox bbox = 1;");
	child = PBChild(str);
	child.comments ~= "// This is a comment";
	ans = "\t/// This is a comment\n\tNullable!(HeaderBBox) bbox;";
	assert(toD(child, 1) == ans);
}

private string constructMismatchException(string type, int indentCount) {
	auto code = CodeBuilder(indentCount);
	code.put("throw new Exception(\"Invalid wiretype \" ~\n");
	code.put("   to!(string)(wireType) ~\n");
	code.put("   \" for variable type "~type~"\");\n\n");
	return code.finalize();
}

private string constructUndecided(PBChild child, int indentCount, Memory mem) {
	auto code = CodeBuilder(indentCount);
	code.mem(mem);
	// this covers enums and classes,
	// since enums are declared as classes
	// also, make sure we don't think we're root
	with(child) {
		code.put("static if (is("~type~" == struct)) {\n", Indent.open);
		code.build("} else\n", Indent.close | Indent.open);
		code.build("static assert(0,\n");
		code.build("  \"Can't identify type `" ~ type ~ "`\");\n");
		code.build(Indent.close);
		code.pushBuild();

		code.put("if(wireType != WireType.lenDelimited)\n", Indent.open);
		code.rawPut(constructMismatchException(type, code.indentCount));
		code.put(Indent.close);

		// no need to worry about packedness here, since it can't be
		code.putBuild("tname");
		code.rawPut(" "~type~"(input,false);\n");
		code.put("} else static if (is("~type~" == enum)) {\n",
		      Indent.close | Indent.open);

		// worry about packedness here
		code.put("if (wireType == WireType.varint) {\n", Indent.open);
		code.build("} else\n", Indent.close | Indent.open);
		code.buildRaw(constructMismatchException(type, code.indentCount));
		code.build(Indent.close);
		code.pushBuild();

		code.putBuild("tname");
		code.rawPut(" cast("~toDType(type)~")\n");
		code.put("   fromVarint!(int)(input);\n");
		if (modifier == "repeated") {
			code.put("} else if (wireType == WireType.lenDelimited) {\n",
			       Indent.close | Indent.open);
			code.putBuild("tname");
			code.rawPut("\n");
			code.put("   fromPacked!("~toDType(type)~
				",fromVarint!(int))(input);\n");
		}
	}
	return code.finalize();
}

string genDes(PBChild child, int indentCount = 0, bool is_exten = false) {
	auto code = CodeBuilder(indentCount);
	with(child) {
		if(type == "group")
			throw new Exception("Group type not supported");

		string tname = name;
		if (is_exten) tname = "__exten"~tname;
		if (is_dep) tname ~= "_dep";
		if(isReserved(tname)) {
			tname = tname ~ "_";
		}
		if (modifier == "repeated") {
			code.build("if(");
			code.buildRaw(tname);
			code.buildRaw(".isNull) ");
			code.buildRaw(tname);
			code.buildRaw(" = new "~toDType(type)~"[](0);\n");
			code.build(tname ~ " ~=");
		} else {
			code.build(tname);
			code.buildRaw(" =");
		}
		code.saveBuild("tname");

		// check header ubyte with case since we're guaranteed to be in a switch
		code.put("case "~to!(string)(index)~":", Indent.open);
		code.push("break;\n");

		code.rawPut("// Deserialize member ");
		code.rawPut(to!(string)(index));
		code.rawPut(" Field Name " ~ name ~ "\n");

		// Class and Enum will have an undecided type
		if(wTFromType(type) == WireType.undecided) {
			code.rawPut(constructUndecided(child, code.indentCount, code.mem));
			return code.finalize();
		}

		// Handle Packed type
		if (packed) {
			assert(modifier == "repeated");
			assert(isPackable(type));
			// Allow reading data even when not packed
			code.put("if (wireType != WireType.lenDelimited)\n", Indent.open);
			code.push(Indent.close);
		}

		// Verify wire type is expected type else
		// this is not condoned, wiretype is invalid, so explode!
		code.put("if (wireType != WireType." ~
			to!(string)(wTFromType(type))~")\n", Indent.open);
		code.rawPut(constructMismatchException(type, code.indentCount));
		code.put(Indent.close);

		if (packed)
			code.pop();

		string pack;
		switch(type) {
		case "float","double","sfixed32","sfixed64","fixed32","fixed64":
			pack = "fromByteBlob!("~toDType(type)~")";
			break;
		case "bool","int32","int64","uint32","uint64":
			pack = "fromVarint!("~toDType(type)~")";
			break;
		case "sint32","sint64":
			pack = "fromSInt!("~toDType(type)~")";
			break;
		case "string","bytes":
			// no need to worry about packedness here, since it can't be
			code.putBuild("tname");
			code.rawPut("\n");
			code.put("   fromByteString!("~toDType(type)~")(input);\n");
			return code.finalize();
		default:
			assert(0, "class/enum/group handled by undecided type.");
		}

		if(packed) {
			code.put("if (wireType == WireType.lenDelimited) {\n", Indent.open);
			code.putBuild("tname");
			code.rawPut("\n");
			code.put("   fromPacked!("~toDType(type)~","~pack~")(input);\n");
			code.put("//Accept data even when not packed\n");
			code.put("} else {\n", Indent.close | Indent.open);
			code.push("}\n");
		}

		code.putBuild("tname");
		code.rawPut(" ");
		code.rawPut(pack ~ "(input);\n");
		return code.finalize();
	}
}

string genSer(PBChild child, int indentCount = 0, bool is_exten = false) {
	auto code = CodeBuilder(indentCount);
	with(child) {
		if(type == "group")
			throw new Exception("Group type not supported");
		code.put("// Serialize member ");
		code.rawPut(to!(string)(index));
		code.rawPut(" Field Name " ~ name ~ "\n");

		string func;
		bool customType = false;
		switch(type) {
		case "float","double","sfixed32","sfixed64","fixed32","fixed64":
			func = "toByteBlob";
			break;
		case "bool","int32","int64","uint32","uint64":
			func = "toVarint";
			break;
		case "sint32","sint64":
			func = "toSInt";
			break;
		case "string","bytes":
			// the checks ensure that these can never be packed
			func = "toByteString";
			break;
		default:
			// this covers defined messages and enums
			func = "toVarint";
			customType = true;
			break;
		}
		auto tname = (is_exten?"__exten":"") ~ name;

		if(is_dep) tname ~= "_dep";
		if(isReserved(tname))
			tname ~= "_";
		code.buildRaw(tname);
		code.saveBuild("tname");

		if (modifier == "repeated" && !packed) {
			code.put("if(!"~tname~".isNull)\n");
			code.put("foreach(iter;");
			code.putBuild("tname");
			code.rawPut(".get()) {\n", Indent.open);
			code.push("}\n");
			code.buildRaw("iter");
			code.saveBuild("tname");
		}

		// we have to have some specialized code to deal with enums vs
		// user-defined classes, since they are both detected the same
		if (customType) {
			code.put("static if (is("~type~" == struct)) {\n", Indent.open);
			code.build("} else\n", Indent.close | Indent.open);
			code.build("static assert(0,\"Can't identify type `");
			code.buildRaw(type ~ "`\");\n");
			code.build(Indent.close);
			code.pushBuild();
			// packed only works for primitive types, so take care of normal
			// repeated serialization here since we can't easily detect this
			// without decent type resolution in the .proto parser
			if (packed) {
				assert(modifier == "repeated");
				code.put("foreach(iter;");
				code.putBuild("tname");
				code.put(") {\n", Indent.open);
				code.push("}\n");
			} else if (modifier != "required" && modifier != "repeated") {
				code.put("if (!");
				code.putBuild("tname");
				code.rawPut(".isNull) ");
			} else
				code.put(""); // Adds indenting

			code.rawPut("ret ~= ");
			if (packed)
				code.rawPut("iter");
			else
				code.putBuild("tname");
			code.rawPut(".Serialize("~to!(string)(index)~");\n");

			if (packed)
				code.pop();
			// done taking care of unpackable classes
			code.put("} else static if (is("~type~" == enum)) {\n",
			         Indent.close | Indent.open);
		}
		// take care of packed circumstances
		if (packed) {
			assert(modifier == "repeated");
			auto packType = toDType(type);
			if(customType)
				packType = "int";
			code.put("if(!");
			code.putBuild("tname");
			code.rawPut(".isNull)\n", Indent.open);
			code.put("ret ~= toPacked!("~packType~"[],"~func~")");
			code.put(Indent.close);
		} else if (modifier != "required" && modifier != "repeated") {
			code.put("if (!");
			code.putBuild("tname");
			code.rawPut(".isNull) ");
		} else
			code.put(""); // Adds indenting

		if(!packed)
			code.rawPut("ret ~= "~func);
		// finish off the parameters, because they're the same for packed or not
		// finish off the parameters, because they're the same for packed or not
		if(customType) {
			if(packed)
				code.rawPut("(cast(int[])");
			else
				code.rawPut("(cast(int)");
		} else
			code.rawPut("(");

		if(modifier != "repeated" && !packed)
			code.rawPush(".get(),", Indent.none);
		else
			code.rawPush(",", Indent.none);

		code.putBuild("tname");
		code.pop();
		code.rawPut(to!(string)(index)~");\n");

	}
	return code.finalize();
}

version(D_Version2)
unittest {
	PBChild child;

	// Optional messages don't ser if missing issue #27
	auto str = ParserData("optional SomeMessage sm = 2;");
	child = PBChild(str);
	mixin(`enum one = ParserData("message AnyLineDescriptor {
                                 optional SomeMessage m2 = 2; }");`);
	mixin(`enum two = ParserData("message SomeMessage {}");`);
	mixin(`enum ichi = PBCompileTime(one);`);
	mixin(`enum ni = PBCompileTime(two);`);
	mixin(`import ProtocolBuffer.conversion.pbbinary;`);
	mixin(`import std.typecons;`);
	mixin("static " ~ ni.toD);
	mixin("static " ~ ichi.toD);
	AnyLineDescriptor ald;
	ald.Serialize();
}

/**
 */
string toD(PBEnum child, int indentCount = 0) {
	auto code = CodeBuilder(indentCount);
	with(child) {
		// Apply comments to enum
		code.rawPut(addComments(comments, code.indentCount));

		code.put("enum "~name~" {\n", Indent.open);
		code.push("}\n");
		foreach (key, value; values) {
			// Apply comments to field
			if(key in valueComments)
				code.rawPut(addComments(valueComments[key], code.indentCount));
			else
				code.put("///\n");

			code.put(value~" = "~to!(string)(key)~",\n");
		}
	}
	return code.finalize();
}

version(D_Version2)
unittest {
	mixin(`enum str = ParserData("enum potato
                                 {TOTALS = 1;JUNK= 5 ; ALL =3;}");`);
	mixin(`enum enm = PBCTEnum(str);`);
	mixin(`import ProtocolBuffer.conversion.pbbinary;`);
	mixin(`import std.typecons;`);
	mixin(enm.toD);
	assert(potato.TOTALS == 1);
	assert(potato.JUNK == 5);
	assert(potato.ALL == 3);

	// Conversion for commented, indented
	auto str2 = ParserData("enum potato{
                           // The total
                           // Set to 1
                           TOTALS = 1;}");
	auto enm2 = PBEnum(str2);
	enm2.comments ~= "// My food";
	auto ans = regex(r"\t/// My food\n"
r"\tenum potato \{\n" ~
r"\t\t/// The total\n" ~
r"\t\t/// Set to 1\n" ~
r"\t\tTOTALS = \d,\n" ~
r"\t\}");
	assert(!enm2.toD(1).match(ans).empty);
}

string genDes(PBMessage msg, int indentCount = 0) {
	auto code = CodeBuilder(indentCount);
	string ret = "";
	with(msg) {
		// add comments
		code.put("// if we're root, we can assume we own the whole string\n");
		code.put("// if not, the first thing we need to do is pull the length that belongs to us\n");
		code.put("static "~name~" Deserialize(ubyte[] manip) {\n", Indent.open);
		code.put("return "~name~"(manip,true);\n");
		code.put("}\n", Indent.close);
		code.put("this(ubyte[] manip,bool isroot=true) {\n", Indent.open);
		code.put("this(manip,isroot);\n");
		code.put("}\n", Indent.close);
		code.put("this(ref ubyte[] manip,bool isroot=true) {\n", Indent.open);
		code.push("}\n");
		code.put("ubyte[] input = manip;\n");

		code.put("// cut apart the input string\n");
		code.put("if (!isroot) {\n", Indent.open);
		code.push("}\n");
		code.put("uint len = fromVarint!(uint)(manip);\n");
		code.put("input = manip[0..len];\n");
		code.put("manip = manip[len..$];\n");
		code.pop();

		// deserialization code goes here
		code.put("while(input.length) {\n", Indent.open);
		code.push("}\n");
		code.put("int header = fromVarint!(int)(input);\n");
		code.put("auto wireType = getWireType(header);\n");
		code.put("switch(getFieldNumber(header)) {\n");
		code.push("}\n");
		//here goes the meat, handily, it is generated in the children
		foreach(pbchild;children) {
			code.rawPut(genDes(pbchild, code.indentCount));
		}
		foreach(pbchild;child_exten) {
			code.rawPut(genDes(pbchild, code.indentCount, true));
		}
		// take care of default case
		code.put("default:\n", Indent.open);
		code.push("break;\n");
		code.put("	// rip off unknown fields\n");
		code.put("if(input.length)\n", Indent.open);
		code.put("ufields ~= toVarint(header)~\n");
		code.put("   ripUField(input,getWireType(header));\n");
		code.pop();
		code.pop();
		code.pop();

		// check for required fields
		foreach(pbchild;child_exten) if (pbchild.modifier == "required") {
			code.put("if (_has__exten_"~pbchild.name~" == false)\n", Indent.open);
			code.put("throw new Exception(\"Did not find a "~pbchild.name~" in the message parse.\");\n");
			code.put(Indent.close);
		}
		foreach(pbchild;children) if (pbchild.modifier == "required") {
			auto field = pbchild.name;
			if(isReserved(field))
				field = field ~ "_";
			code.put("if ("~field~".isNull) throw new Exception(\"Did not find a "~field~" in the message parse.\");\n");
		}
		return code.finalize();
	}
}

string genSer(PBMessage msg, int indentCount = 0) {
	auto indent = indented(indentCount);
	string ret = "";
	with(msg) {
		// use -1 as a default value, since a nibble can not produce that number
		ret ~= indent~"ubyte[] Serialize(int field = -1) const {\n";
		indent = indented(++indentCount);
		// codegen is fun!
		ret ~= indent~"ubyte[] ret;\n";
		// serialization code goes here
		foreach(pbchild;children) {
			ret ~= genSer(pbchild, indentCount);
		}
		foreach(pbchild;child_exten) {
			ret ~= genSer(pbchild, indentCount,true);
		}
		// tack on unknown bytes
		ret ~= indent~"ret ~= ufields;\n";

		// include code to determine if we need to add a tag and a length
		ret ~= indent~"// take care of header and length generation if necessary\n";
		ret ~= indent~"if (field != -1) {\n";
		// take care of length calculation and integration of header and length
		ret ~= indented(indentCount+1)~"ret = genHeader(field,WireType.lenDelimited)~toVarint(ret.length,field)[1..$]~ret;\n";
		ret ~= indent~"}\n";

		ret ~= indent~"return ret;\n";
		indent = indented(--indentCount);
		ret ~= indent~"}\n";
	}
	return ret;
}
string genMerge(PBMessage msg, int indentCount = 0) {
	auto indent = indented(indentCount);
	string ret = "";
	with(msg) {
		ret ~= indent~"void MergeFrom("~name~" merger) {\n";
		indent = indented(++indentCount);
		// merge code
		foreach(pbchild;children) {
			auto field = pbchild.name;
			if(pbchild.is_dep) field ~= "_dep";
			if(isReserved(field))
				field = field ~ "_";
			if (pbchild.modifier != "repeated") {
			ret ~= indent~"if (!merger."~field~".isNull) "~
				field~" = merger."~field~";\n";
			} else {
				ret ~= indent~"if (!merger."~field~".isNull) "~
					field~" ~= merger."~field~";\n";
			}
		}
		indent = indented(--indentCount);
		ret ~= indent~"}\n";
		return ret;
	}
}

/**
 */
string toD(PBMessage msg, int indentCount = 0) {
	auto indent = indented(indentCount);
	string ret = "";
	with(msg) {
		ret ~= addComments(comments, indentCount);

		ret ~= indent~(indent.length?"static ":"")~"struct "~name~" {\n";
		indent = indented(++indentCount);
		ret ~= indent~"// deal with unknown fields\n";
		ret ~= indent~"ubyte[] ufields;\n";
		// fill the class with goodies!
		// first, we'll do the enums!
		foreach(pbenum;enum_defs) {
			ret ~= toD(pbenum, indentCount);
			ret ~= "\n\n";
		}
		// now, we'll do the nested messages
		foreach(pbmsg;message_defs) {
			ret ~= toD(pbmsg, indentCount);
			ret ~= "\n\n";
		}
		// do the individual instantiations
		foreach(pbchild;children) {
			ret ~= toD(pbchild, indentCount);
			ret ~= "\n";
		}
		// last, do the extension instantiations
		foreach(pbchild;child_exten) {
			ret ~= pbchild.genExtenCode(indent);
			ret ~= "\n";
		}
		ret ~= "\n";
		// here is where we add the code to serialize and deserialize
		ret ~= genSer(msg, indentCount);
		ret ~= "\n";
		ret ~= genDes(msg, indentCount);
		ret ~= "\n";
		// define merging function
		ret ~= genMerge(msg, indentCount);
		ret ~= "\n";
		// deal with what little we need to do for extensions
		ret ~= extensions.genExtString(indent~"static ");

		// guaranteed to work, since we tack on a tab earlier
		indent = indented(--indentCount);
		ret ~= indent~"}\n";
	}
	return ret;
}

bool isReserved(string field) {
	string[] words = [
"Error", "Exception", "Object", "Throwable", "__argTypes", "__ctfe",
	"__gshared", "__monitor", "__overloadset", "__simd", "__traits",
	"__vector", "__vptr", "_argptr", "_arguments", "_ctor", "_dtor",
	"abstract", "alias", "align", "assert", "auto", "body", "bool", "break",
	"byte", "cast", "catch", "cdouble", "cent", "cfloat", "char", "class",
	"const", "contained", "continue", "creal", "dchar", "debug", "delegate",
	"delete", "deprecated", "do", "double", "dstring", "else", "enum",
	"export", "extern", "false", "final", "finally", "float", "float", "for",
	"foreach", "foreach_reverse", "function", "goto", "idouble", "if",
	"ifloat", "immutable", "import", "in", "in", "inout", "int", "int",
	"interface", "invariant", "ireal", "is", "lazy", "lazy", "long", "long",
	"macro", "mixin", "module", "new", "nothrow", "null", "out", "out",
	"override", "package", "pragma", "private", "protected", "public", "pure",
	"real", "ref", "return", "scope", "shared", "short", "static", "string",
	"struct", "super", "switch", "synchronized", "template", "this", "throw",
	"true", "try", "typedef", "typeid", "typeof", "ubyte", "ucent", "uint",
	"uint", "ulong", "ulong", "union", "unittest", "ushort", "ushort",
	"version", "void", "volatile", "wchar", "while", "with", "wstring"];

	foreach(string w; words)
		if(w == field)
			return true;
	return false;
}

string addComments(string[] comments, int indentCount) {
	auto code = CodeBuilder(indentCount);
	foreach(c; comments) {
		if(c.length > 1)
			code.put((c[0..2] == "//") ? "/":"");
		else
			code.put("");
		code.rawPut(c~"\n");
	}
	if(comments.empty())
		code.put("///\n");
	return code.finalize();
}

unittest {
	assert(isReserved("version"));
}

version(D_Version2)
unittest {
	// Conversion for optional
	mixin(`enum str = ParserData("message Test1 { required int32 a = 1; }");`);
	mixin(`enum msg = PBCompileTime(str);`);
	mixin(`import ProtocolBuffer.conversion.pbbinary;`);
	mixin(`import std.typecons;`);
	mixin("static " ~ msg.toD);
	ubyte[] feed = [0x08,0x96,0x01]; // From example
	auto t1 = Test1(feed);
	assert(t1.a == 150);
	assert(t1.Serialize() == feed);
}

version(D_Version2)
unittest {
	auto str = ParserData("optional OtherType type = 1;");
	auto ms = PBChild(str);
	toD(ms);
}

version(D_Version2)
unittest {
	// Conversion for repated packed
	mixin(`enum str = ParserData("message Test4 {
	                              repeated int32 d = 4 [packed=true]; }");`);
	mixin(`enum msg = PBCompileTime(str);`);
	mixin(`import ProtocolBuffer.conversion.pbbinary;`);
	mixin(`import std.typecons;`);
	mixin("static " ~ msg.toD);
	ubyte[] feed = [0x22, // Tag (field number 4, wire type 2)
		0x06, // payload size (6 bytes)
		0x03, // first element (varint 3)
		0x8E,0x02, // second element (varint 270)
		0x9E,0xA7,0x05 // third element (varint 86942)
			]; // From example
	auto t4 = Test4(feed);
	assert(t4.d == [3,270,86942]);
	assert(t4.Serialize() == feed);
}

version(D_Version2)
unittest {
	// Conversion for string
	mixin(`enum str = ParserData("message Test2 {
	                              required string b = 2; }");`);
	mixin(`enum msg = PBCompileTime(str);`);
	mixin(`import ProtocolBuffer.conversion.pbbinary;`);
	mixin(`import std.typecons;`);
	mixin("static " ~ msg.toD);
	ubyte[] feed = [0x12,0x07, // (tag 2, type 2) (length 7)
		0x74,0x65,0x73,0x74,0x69,0x6e,0x67
			]; // From example
	auto t2 = Test2(feed[]);
	assert(t2.b == "testing");
	assert(t2.Serialize() == feed);
}

version(D_Version2)
unittest {
	// Tests parsing does not pass message
	mixin(`enum str = ParserData("message Test2 {
	                              repeated string b = 2;
	                              repeated string c = 3; }");`);
	mixin(`enum msg = PBCompileTime(str);`);
	mixin(`import ProtocolBuffer.conversion.pbbinary;`);
	mixin(`import std.typecons;`);
	mixin("static " ~ msg.toD);
	ubyte[] feed = [0x09,(2<<3) | 2,0x07,
		0x74,0x65,0x73,0x74,0x69,0x6e,0x67,
		3<<3 | 0,0x08
			];
	auto feedans = feed;
	auto t2 = Test2(feed, false);
	assert(t2.b == ["testing"]);
	assert(t2.Serialize() == feedans[1..$-2]);
}

version(D_Version2)
unittest {
	// Packed enum data
	mixin(`enum um = ParserData("enum MyNum {
	                              YES = 1; NO = 2; }");`);
	mixin(`enum str = ParserData("message Test {
	                              repeated MyNum b = 2 [packed=true]; }");`);
	mixin(`enum msg = PBCompileTime(str);`);
	mixin(`enum yum = PBCTEnum(um);`);
	mixin(`import ProtocolBuffer.conversion.pbbinary;`);
	mixin(`import std.typecons;`);
	mixin(yum.toD);
	mixin("static " ~ msg.toD);
	ubyte[] feed = [(2<<3) | 2,0x02,
		0x01,0x02
			];
	auto t = Test(feed);
	assert(t.b == [MyNum.YES, MyNum.NO]);
	assert(t.Serialize() == feed);
}

version(D_Version2)
unittest {
	// Type Generation
	mixin(`enum one = ParserData("enum Settings {
	                              FOO = 1;
	                              BAR = 2;
	                          }");`);
	mixin(`enum two = ParserData("message Type {
	                              repeated int32 data = 1;
	                              repeated int32 extra = 2 [packed = true];
	                              optional int32 last = 3;
	                          }");`);
	mixin(`enum three = ParserData("message OtherType {
	                              optional Type struct = 1;
	                              repeated Settings enum = 2 [packed = true];
	                              repeated Settings num = 3;
	                              repeated string a = 4;
	                              required string b = 5;
	                              repeated Type t = 6;
	                          }");`);
	mixin(`enum ichi = PBCTEnum(one);`);
	mixin(`enum ni = PBCompileTime(two);`);
	mixin(`enum san = PBCompileTime(three);`);
	mixin(`import ProtocolBuffer.conversion.pbbinary;`);
	mixin(`import std.typecons;`);
	mixin(ichi.toD);
	mixin("static " ~ ni.toD);
	mixin("static " ~ san.toD);
	ubyte[] feed = [((1 << 3) | 2), 8, // OtherType.Type
	((1 << 3) | 0), 1, ((1 << 3) | 0), 2, // Type.Data
	((2 << 3) | 2), 2, 3, 4, // Type.Extra

	((2 << 3) | 2), 1, 1, // OtherType.enum
	((3 << 3) | 0), 2, // OtherType.num
	((4 << 3) | 2), 1, 'a', // OtherType.a
	((4 << 3) | 2), 1, 'b', // OtherType.a
	((5 << 3) | 2), 2, 'c', 'd', // OtherType.b

	((6 << 3) | 2), 4, // OtherType.Type
	((1 << 3) | 0), 2, // Type.Data
	((1 << 3) | 0), 2, // Type.Data
	((6 << 3) | 2), 2, // OtherType.Type
	((1 << 3) | 0), 3, // Type.Data
	];
	auto ot = OtherType(feed);
	assert(ot.struct_.data == [1, 2]);
	assert(ot.struct_.extra == [3, 4]);
	assert(ot.enum_ == [Settings.FOO]);
	assert(ot.num == [Settings.BAR]);
	assert(ot.a == ["a", "b"]);
	assert(ot.b == "cd");
	assert(ot.t[0].data == [2,2]);
	assert(ot.t[1].data == [3]);
	assert(ot.t.length == 2);

	auto res = ot.Serialize();
	assert(res == feed);
}
