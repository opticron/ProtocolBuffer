/**
 * This module provides conversion functionality of different elements
 * to the D Programming Language which are campatible with version 1.
 */
module ProtocolBuffer.conversion.d1lang;

import ProtocolBuffer.pbgeneral;
import ProtocolBuffer.pbchild;
import ProtocolBuffer.pbenum;
import ProtocolBuffer.pbmessage;
import ProtocolBuffer.conversion.common;
import ProtocolBuffer.conversion.pbbinary;

version(D_Version2) {
	import std.algorithm;
	import std.range;
	import std.regex;
} else
	import ProtocolBuffer.d1support;

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
		return format("%s[]", toDType(child.type));
	else
		return format("%s", toDType(child.type));
}

/**
 */
string toD1(PBChild child, int indentCount = 0) {
	string ret;
	auto indent = indented(indentCount);
	with(child) {
		ret ~= indent~toDType(type)~(modifier=="repeated"?"[]_":" _")~name~(valdefault.length?" = "~valdefault:"")~";\n";

		foreach(c; comments)
			ret ~= indent ~ (c.empty() ? "":"/") ~ c ~ "\n";
		if(comments.empty())
			ret ~= indent ~ "///\n";
		// get accessor
		ret ~= indent~(is_dep?"deprecated ":"")~toDType(type)~(modifier=="repeated"?"[]":" ")~name~"() {\n";
		ret ~= indent~"	return _"~name~";\n";
		ret ~= indent~"}\n";

		if(!comments.empty())
			ret ~= indent ~ "/// ditto\n";
		else
			ret ~= indent ~ "///\n";
		// set accessor
		ret ~= indent~(is_dep?"deprecated ":"")~"void "~name~"("~toDType(type)~(modifier=="repeated"?"[]":" ")~"input_var) {\n";
		ret ~= indent~"	_"~name~" = input_var;\n";

		if (modifier != "repeated") ret ~= indent~"	_has_"~name~" = true;\n";
		ret ~= indent~"}\n";
		if (modifier == "repeated") {
			ret ~= indent~(is_dep?"deprecated ":"")~"bool has_"~name~" () {\n";
			ret ~= indent~"	return _"~name~".length?1:0;\n";
			ret ~= indent~"}\n";
			ret ~= indent~(is_dep?"deprecated ":"")~"void clear_"~name~" () {\n";
			ret ~= indent~"	_"~name~" = null;\n";
			ret ~= indent~"}\n";
			// technically, they can just do class.item.length
			// there is no need for this
			ret ~= indent~(is_dep?"deprecated ":"")~"int "~name~"_size () {\n";
			ret ~= indent~"	return _"~name~".length;\n";
			ret ~= indent~"}\n";
			// functions to do additions, both singular and array
			ret ~= indent~(is_dep?"deprecated ":"")~"void add_"~name~" ("~toDType(type)~" __addme) {\n";
			ret ~= indent~"	_"~name~" ~= __addme;\n";
			ret ~= indent~"}\n";
			ret ~= indent~(is_dep?"deprecated ":"")~"void add_"~name~" ("~toDType(type)~"[]__addme) {\n";
			ret ~= indent~"	_"~name~" ~= __addme;\n";
			ret ~= indent~"}\n";
		} else {
			ret ~= indent~"bool _has_"~name~" = false;\n";
			ret ~= indent~(is_dep?"deprecated ":"")~"bool has_"~name~" () {\n";
			ret ~= indent~"	return _has_"~name~";\n";
			ret ~= indent~"}\n";
			ret ~= indent~(is_dep?"deprecated ":"")~"void clear_"~name~" () {\n";
			ret ~= indent~"	_has_"~name~" = false;\n";
			ret ~= indent~"}\n";
		}
		return ret;
    }
}

version(D_Version2)
unittest {
	PBChild child;

	// Conversion for optional
	auto str = ParserData("optional HeaderBBox bbox = 1;");
	child = PBChild(str);
    assert(!child.toD1().find(r"bbox(HeaderBBox").empty);
    assert(!child.toD1().find(r"bbox()").empty);
    assert(!child.toD1().find(r"has_bbox").empty);
    assert(!child.toD1().find(r"clear_bbox").empty);

	// Conversion for repeated
	str = ParserData("repeated HeaderBBox bbox = 1;");
	child = PBChild(str);
    assert(!child.toD1().find(r"bbox(HeaderBBox[]").empty);
    assert(!child.toD1().find(r"bbox()").empty);
    assert(!child.toD1().find(r"has_bbox").empty);
    assert(!child.toD1().find(r"clear_bbox").empty);
    assert(!child.toD1().find(r"add_bbox").empty);

	// Conversion for required
	str = ParserData("required int32 value = 1;");
	child = PBChild(str);

	// Conversion for default value
	str = ParserData("required int64 value = 1 [default=6]; ");
	child = PBChild(str);
    assert(child.toD1().startsWith(r"long _value = 6;"));

	// Conversion for default, negative, deprecated value
	str = ParserData("optional int64 value = 1 [default=-32,deprecated=true];");
	child = PBChild(str);
    assert(child.toD1().startsWith(r"long _value = -32;"));
    assert(!child.toD1().find(r"deprecated long value()").empty);

	// Conversion for commented, indented
	str = ParserData("optional HeaderBBox bbox = 1;");
	child = PBChild(str);
	child.comments ~= "// This is a comment";
    assert(!child.toD1().find(r"/// This is a comment").empty);
    assert(!child.toD1().find(r"/// ditto").empty);
}

private string constructMismatchException(string type, int indentCount) {
	auto indent = indented(indentCount);
	auto ret = indent ~ "throw new Exception(\"Invalid wiretype \" ~\n";
		ret ~= indent ~ "   makeString(wireType) ~\n";
		ret ~= indent ~ "   \" for variable type "~type~"\");\n\n";
	return ret;
}

private string constructUndecided(PBChild child, int indentCount, string tname) {
	string ret;
	// this covers enums and classes,
	// since enums are declared as classes
	// also, make sure we don't think we're root
	with(child) {
		ret ~= indented(indentCount++)~"static if (is("~type~":Object)) {\n";
		ret ~= indented(indentCount) ~
			"if(wireType != WireType.lenDelimited)\n";
		ret ~= constructMismatchException(type, indentCount+1);

		// no need to worry about packedness here, since it can't be
		if(modifier == "repeated") {
			ret ~= indented(indentCount)~"add_"~tname~"(\n";
			ret ~= indented(indentCount)~"   "~type~
				".Deserialize(input,false));\n";
		} else {
			ret ~= indented(indentCount)~tname~" =\n";
			ret ~= indented(indentCount)~"   "~type~
				".Deserialize(input,false);\n";
		}
		ret ~= indented(--indentCount)~
			"} else static if (is("~type~" == enum)) {\n";
		ret ~= indented(++indentCount) ~
			"if(wireType != WireType.varint)\n";
		ret ~= constructMismatchException(type, indentCount+1);

		// worry about packedness here
		ret ~= indented(indentCount++)~"if (wireType == WireType.varint) {\n";
		if (modifier != "repeated") {
			ret ~= indented(indentCount)~tname~" =\n";
			ret ~= indented(indentCount)~"   cast("~toDType(type)~")\n";
			ret ~= indented(indentCount)~"   fromVarint!(int)(input);\n";
		} else {
			ret ~= indented(indentCount)~"add_"~tname~"(\n";
			ret ~= indented(indentCount)~"   cast("~toDType(type)~")\n";
			ret ~= indented(indentCount)~"   fromVarint!(int)(input));\n";
			ret ~= indented(--indentCount)~"} else if (wireType == WireType.lenDelimited) {\n";
			ret ~= indented(++indentCount)~tname~" =\n";
			ret ~= indented(indentCount)~"   fromPacked!("~toDType(type)~
				",fromVarint!(int))(input);\n";
			ret ~= indented(indentCount)~tname~" =\n";
			ret ~= indented(indentCount)~"   fromPacked!("~toDType(type)~
				",fromVarint!(int))(input);\n";
		}
		ret ~= indented(--indentCount)~"}\n";
		ret ~= indented(--indentCount)~"} else\n";
		ret ~= indented(indentCount+1) ~ "static assert(0,\n";
		ret ~= indented(indentCount+1) ~
			"  \"Can't identify type `" ~ type ~ "`\");\n";
	}
	return ret;
}

string genDes(PBChild child, int indentCount = 0, bool is_exten = false) {
	string ret;
	auto indent = indented(indentCount);
	with(child) {
		if(type == "group")
			throw new Exception("Group type not supported");

		string tname = name;
		if (is_exten) tname = "__exten"~tname;
		// check header ubyte with case since we're guaranteed to be in a switch
		ret ~= indent~"case "~to!(string)(index)~":\n";
		indent = indented(++indentCount);

		// Class and Enum will have an undecided type
		if(wTFromType(type) == WireType.undecided)
			return ret ~ constructUndecided(child, indentCount, tname);

		// Handle Packed type
		if (packed) {
			assert(modifier == "repeated");
			assert(isPackable(type));
			// Allow reading data even when not packed
			ret ~= indent~"if (wireType != WireType.lenDelimited)\n";
			++indentCount;
		}

		// Verify wire type is expected type else
		// this is not condoned, wiretype is invalid, so explode!
		ret ~= indented(indentCount)~"if (wireType != " ~
			to!(string)(cast(byte)wTFromType(type))~")\n";
		ret ~= constructMismatchException(type, indentCount+1);

		if (packed)
			--indentCount;

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
			if(modifier == "repeated") {
				ret ~= indented(indentCount)~"add_"~tname ~ "(\n";
				ret ~= indented(indentCount)~"   fromByteString!("~
					toDType(type)~")(input));\n";
			} else {
				ret ~= indented(indentCount)~tname ~ " =\n";
				ret ~= indented(indentCount)~"   fromByteString!("~
					toDType(type)~")(input);\n";
			}
			return ret;
		default:
			assert(0, "class/enum/group handled by undecided type.");
		}

		if(packed) {
			ret ~= indented(indentCount++)~
				"if (wireType == WireType.lenDelimited) {\n";
			ret ~= indented(indentCount) ~ "add_" ~ tname ~ "(\n";
			ret ~= indented(indentCount) ~
				"   fromPacked!("~toDType(type)~","~pack~")(input));\n";
			ret ~= indented(--indentCount) ~
				"//Accept data even when not packed\n";
			ret ~= indented(indentCount++) ~ "} else {\n";
		}

		if(modifier == "repeated") {
			ret ~= indented(indentCount) ~ "add_" ~ tname ~ "(\n";
			ret ~= indented(indentCount) ~ "   " ~ pack ~ "(input));\n";
		} else {
			ret ~= indented(indentCount) ~ tname ~ " =\n";
			ret ~= indented(indentCount) ~ "   " ~ pack ~ "(input);\n";
		}

		if(packed) ret ~= indented(--indentCount) ~ "}\n";

		// tack on the break so we don't have fallthrough
		ret ~= indented(--indentCount)~"break;\n";
		return ret;
	}
}

string genSer(PBChild child, int indentCount = 0, bool is_exten = false) {
	string ret;
	auto indent = indented(indentCount);
	with(child) {
		if(type == "group")
			throw new Exception("Group type not supported");

		string tname = name;
		if (is_exten) tname = "__exten"~tname;
		if (modifier == "repeated" && !packed) {
			ret ~= indent~"foreach(iter;"~tname~") {\n";
			tname = "iter";
			indent = indented(++indentCount);
		}
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
		// we have to have some specialized code to deal with enums vs user-defined classes, since they are both detected the same
		if (customType) {
			ret ~= indent~"static if (is("~type~" : Object)) {\n";
			// packed only works for primitive types, so take care of normal repeated serialization here
			// since we can't easily detect this without decent type resolution in the .proto parser
			if (modifier == "repeated" && packed) {
				ret ~= indent~"foreach(iter;"~name~") {\n";
				indent = indented(++indentCount);
			}
			ret ~= indent~"	ret ~= "~(packed?"iter":tname)~".Serialize("~to!(string)(index)~");\n";
			if (modifier == "repeated" && packed) {
				indent = indented(--indentCount);
				ret ~= indent~"}\n";
			}
			// done taking care of unpackable classes
			ret ~= indent~"} else static if (is("~type~" == enum)) {\n";
			indent = indented(++indentCount);
		}
		// take care of packed circumstances
		ret ~= indent;
		if (packed) {
			assert(modifier == "repeated");
			auto packType = toDType(type);
			if(customType)
				packType = "int";
			ret ~= "if(!has_"~tname~")\n" ~ indented(indentCount+1);
			ret ~= "ret ~= toPacked!("~packType~"[],"~func~")";
		} else {
			if (modifier != "repeated" && modifier != "required")
				ret ~= "if (!has_"~tname~") ";
			ret ~= "ret ~= "~func;
		}
		// finish off the parameters, because they're the same for packed or not
		if(tname != "iter") {
			if(packed && customType)
				tname = "cast(int[])" ~ tname;
		}
		ret ~= "("~tname~","~to!(string)(index)~");\n";
		if (customType) {
			ret ~= indented(--indentCount)~"} else\n";
			ret ~= indented(indentCount+1)~
				"static assert(0,\"Can't identify type `"
				~ type ~ "`\");\n";
		}
		if (modifier == "repeated" && !packed) {
			ret ~= indented(--indentCount)~"}\n";
		}
	}
	return ret;
}

/**
 */
string toD1(PBEnum child, int indentCount = 0) {
	auto indent = indented(indentCount);
	string ret = "";
	with(child) {
		// Apply comments to enum
		foreach(c; comments)
			ret ~= indent ~ (c.empty() ? "":"/") ~ c ~ "\n";

		ret ~= indent~"enum "~name~" {\n";
		foreach (key, value; values) {
			// Apply comments to field
			if(key in valueComments)
				foreach(c; valueComments[key])
					ret ~= indent ~ "\t/" ~ c ~ "\n";

			ret ~= indent~"\t"~value~" = "~to!(string)(key)~",\n";
		}
		ret ~= indent~"}";
	}
	return ret;
}

version(D_Version2)
unittest {
	auto str = ParserData("enum potato {TOTALS = 1;JUNK= 5 ; ALL =3;}");
	auto enm = PBEnum(str);
	auto ans = regex(r"enum potato \{\n" ~
r"\t\w{3,6} = \d,\n" ~
r"\t\w{3,6} = \d,\n" ~
r"\t\w{3,6} = \d,\n\}");
    assert(!enm.toD1.match(ans).empty);
    assert(!enm.toD1.find(r"TOTALS = 1").empty);
    assert(!enm.toD1.find(r"ALL = 3").empty);
    assert(!enm.toD1.find(r"JUNK = 5").empty);

	// Conversion for commented, indented
	str = ParserData("enum potato {\n// The total\nTOTALS = 1;}");
	enm = PBEnum(str);
	enm.comments ~= "// My food";
	ans = regex(r"\t/// My food\n"
r"\tenum potato \{\n" ~
r"\t\t/// The total\n" ~
r"\t\tTOTALS = \d,\n" ~
r"\t\}");
    assert(!enm.toD1(1).match(ans).empty);
}

string genDes(PBMessage msg, int indentCount = 0) {
	auto indent = indented(indentCount);
	string ret = "";
	with(msg) {
		// add comments
		ret ~= indent~"// if we're root, we can assume we own the whole string\n";
		ret ~= indent~"// if not, the first thing we need to do is pull the length that belongs to us\n";
		ret ~= indent~"static "~name~" Deserialize(ref ubyte[] manip, bool isroot=true) {return new "~name~"(manip,isroot);}\n";
		ret ~= indent~"this() { }\n";
		ret ~= indent~"this(ref ubyte[] manip,bool isroot=true) {\n";
		indent = indented(++indentCount);
		ret ~= indent~"ubyte[] input = manip;\n";

		ret ~= indent~"// cut apart the input string\n";
		ret ~= indent~"if (!isroot) {\n";
		indent = indented(++indentCount);
		ret ~= indent~"uint len = fromVarint!(uint)(manip);\n";
		ret ~= indent~"input = manip[0..len];\n";
		ret ~= indent~"manip = manip[len..$];\n";
		indent = indented(--indentCount);
		ret ~= indent~"}\n";

		// deserialization code goes here
		ret ~= indent~"while(input.length) {\n";
		indent = indented(++indentCount);
		ret ~= indent~"int header = fromVarint!(int)(input);\n";
		ret ~= indent~"auto wireType = getWireType(header);\n";
		ret ~= indent~"switch(getFieldNumber(header)) {\n";
		//here goes the meat, handily, it is generated in the children
		foreach(pbchild;children) {
			ret ~= genDes(pbchild, indentCount);
		}
		foreach(pbchild;child_exten) {
			ret ~= genDes(pbchild, indentCount, true);
		}
		// take care of default case
		ret ~= indent~"default:\n";
		ret ~= indent~"	// rip off unknown fields\n";
		ret ~= indent~"	ufields ~= _toVarint(header)~ripUField(input,getWireType(header));\n";
		ret ~= indent~"	break;\n";
		ret ~= indent~"}\n";
		indent = indented(--indentCount);
		ret ~= indent~"}\n";

		// check for required fields
		foreach(pbchild;child_exten) if (pbchild.modifier == "required") {
			ret ~= indent~"if (_has__exten_"~pbchild.name~" == false) throw new Exception(\"Did not find a "~pbchild.name~" in the message parse.\");\n";
		}
		foreach(pbchild;children) if (pbchild.modifier == "required") {
			ret ~= indent~"if (!_has_"~pbchild.name~") throw new Exception(\"Did not find a "~pbchild.name~" in the message parse.\");\n";
		}
		indent = indented(--indentCount);
		ret ~= indent~"}\n";
		return ret;
	}
}

string genSer(PBMessage msg, int indentCount = 0) {
	auto indent = indented(indentCount);
	string ret = "";
	with(msg) {
		// use -1 as a default value, since a nibble can not produce that number
		ret ~= indent~"ubyte[] Serialize(int field = -1) {\n";
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
		ret ~= indented(indentCount+1)~"ret = genHeader(field,2)~toVarint(ret.length,field)[1..$]~ret;\n";
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
		foreach(pbchild;children) if (pbchild.modifier != "repeated") {
			ret ~= indent~"if (merger.has_"~pbchild.name~") "~pbchild.name~" = merger."~pbchild.name~";\n";
		} else {
			ret ~= indent~"if (merger.has_"~pbchild.name~") add_"~pbchild.name~"(merger."~pbchild.name~");\n";
		}
		indent = indented(--indentCount);
		ret ~= indent~"}\n";
		return ret;
	}
}

/**
 */
string toD1(PBMessage msg, int indentCount = 0) {
	auto indent = indented(indentCount);
	string ret = "";
	with(msg) {
		foreach(c; comments)
			ret ~= indent ~ (c.empty() ? "":"/") ~ c ~ "\n";
		ret ~= indent~(indent.length?"static ":"")~"class "~name~" {\n";
		indent = indented(++indentCount);
		ret ~= indent~"// deal with unknown fields\n";
		ret ~= indent~"ubyte[] ufields;\n";
		// fill the class with goodies!
		// first, we'll do the enums!
		foreach(pbenum;enum_defs) {
			ret ~= toD1(pbenum, indentCount);
			ret ~= "\n\n";
		}
		// now, we'll do the nested messages
		foreach(pbmsg;message_defs) {
			ret ~= toD1(pbmsg, indentCount);
			ret ~= "\n\n";
		}
		// do the individual instantiations
		foreach(pbchild;children) {
			ret ~= toD1(pbchild, indentCount);
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

version(D_Version2)
unittest {
    PBMessage PBCompileTime(ParserData pbstring) {
        return PBMessage(pbstring);
    }

	mixin("import std.conv;\n");
	mixin("static string makeString(T)(T v) {\n"~
	"\treturn to!string(v);\n"~
	"}\n");

	// Conversion for optional
	mixin(`enum str = ParserData("message Test1 { required int32 a = 1; }");`);
	mixin(`enum msg = PBCompileTime(str);`);
	mixin(`import ProtocolBuffer.conversion.pbbinary;`);
	mixin(`import std.typecons;`);
	mixin("static " ~ msg.toD1);
	ubyte[] feed = [0x08,0x96,0x01]; // From example
	auto t1 = new Test1(feed);
	assert(t1.a == 150);
	assert(t1.Serialize() == feed);
}

unittest {
	auto str = ParserData("optional OtherType type = 1;");
	auto ms = PBChild(str);
    toD1(ms);
}
