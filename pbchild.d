// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbchild;
import ProtocolBuffer.pbgeneral;

version(D_Version2) import std.range;
else import ProtocolBuffer.d1support;

import std.string;
import std.stdio;
import std.conv;

struct PBChild {
	string modifier;
	string type;
	string name;
	string[] comments;
	int index;
	string valdefault;
	bool packed = false;
	bool is_dep = false;

	string genExtenCode(string indent) {
		string ret;
		ret ~= indent~(is_dep?"deprecated ":"")~toDType(type)~(modifier=="repeated"?"[]":" ")~"__exten_"~name~(valdefault.length?" = "~valdefault:"")~";\n";
		// get accessor
		ret ~= indent~(is_dep?"deprecated ":"")~toDType(type)~(modifier=="repeated"?"[]":" ")~"GetExtension(int T:"~to!(string)(index)~")() {\n";
		ret ~= indent~"	return __exten_"~name~";\n";
		ret ~= indent~"}\n";
		// set accessor
		ret ~= indent~(is_dep?"deprecated ":"")~"void SetExtension(int T:"~to!(string)(index)~")("~toDType(type)~(modifier=="repeated"?"[]":" ")~"input_var) {\n";
		ret ~= indent~"	__exten_"~name~" = input_var;\n";
		if (modifier != "repeated") ret ~= indent~"	_has__exten_"~name~" = true;\n";
		ret ~= indent~"}\n";
		if (modifier == "repeated") {
			ret ~= indent~(is_dep?"deprecated ":"")~"bool HasExtension(int T:"~to!(string)(index)~")() {\n";
			ret ~= indent~"	return __exten_"~name~".length?1:0;\n";
			ret ~= indent~"}\n";
			ret ~= indent~(is_dep?"deprecated ":"")~"void ClearExtension(int T:"~to!(string)(index)~")() {\n";
			ret ~= indent~"	__exten_"~name~" = null;\n";
			ret ~= indent~"}\n";
			// technically, they can just do class.item.length
			// there is no need for this
			ret ~= indent~(is_dep?"deprecated ":"")~"int ExtensionSize(int T:"~to!(string)(index)~")() {\n";
			ret ~= indent~"	return __exten_"~name~".length;\n";
			ret ~= indent~"}\n";
			// functions to do additions, both singular and array
			ret ~= indent~(is_dep?"deprecated ":"")~"void AddExtension(int T:"~to!(string)(index)~")("~toDType(type)~" __addme) {\n";
			ret ~= indent~"	__exten_"~name~" ~= __addme;\n";
			ret ~= indent~"}\n";
			ret ~= indent~(is_dep?"deprecated ":"")~"void AddExtension(int T:"~to!(string)(index)~")("~toDType(type)~"[]__addme) {\n";
			ret ~= indent~"	__exten_"~name~" ~= __addme;\n";
			ret ~= indent~"}\n";
		} else {
			ret ~= indent~"bool _has__exten_"~name~" = false;\n";
			ret ~= indent~(is_dep?"deprecated ":"")~"bool HasExtension(int T:"~to!(string)(index)~")() {\n";
			ret ~= indent~"	return _has__exten_"~name~";\n";
			ret ~= indent~"}\n";
			ret ~= indent~(is_dep?"deprecated ":"")~"void ClearExtension(int T:"~to!(string)(index)~")() {\n";
			ret ~= indent~"	_has__exten_"~name~" = false;\n";
			ret ~= indent~"}\n";
		}
		return ret;
	}

	static PBChild opCall(ref ParserData pbstring)
	in {
		assert(pbstring.length);
	} body {
		PBChild child;
		// all of the modifiers happen to be the same length...whodathunkit
		// also, it's guaranteed to be there by previous code, so it shouldn't need error checking
		child.modifier = pbstring.input[0..8];
		pbstring = pbstring[8..pbstring.length];
		pbstring = stripLWhite(pbstring);
		// now we want to pull out the type
		child.type = stripValidChars(CClass.MultiIdentifier,pbstring);
		if (!child.type.length) throw new PBParseException("Child Instantiation","Could not pull type from definition.", pbstring.line);
		if (!validateMultiIdentifier(child.type)) throw new PBParseException("Child Instantiation","Invalid type identifier "~child.type~".", pbstring.line);
		pbstring = stripLWhite(pbstring);
		// pull out the name of the instance, now
		child.name = stripValidChars(CClass.Identifier,pbstring);
		if (!child.name.length) throw new PBParseException("Child Instantiation("~child.type~")","Could not pull name from definition.", pbstring.line);
		if (!validIdentifier(child.name)) throw new PBParseException("Child Instantiation("~child.type~")","Invalid name identifier "~child.name~".", pbstring.line);
		pbstring = stripLWhite(pbstring);
		// make sure the next character is =, because we need to snag the index, next
		if (pbstring[0] != '=') throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Missing '=' for child instantiation.", pbstring.line);
		pbstring = pbstring[1..pbstring.length];
		pbstring = stripLWhite(pbstring);
		// pull numeric index
		string tmp = stripValidChars(CClass.Numeric,pbstring);
		if (!tmp.length) throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Could not pull numeric index.", pbstring.line);
		child.index = to!(int)(tmp);
		if (child.index <= 0) throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Numeric index can not be less than 1.", pbstring.line);
		if (child.index > (1<<29)-1) throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Numeric index can not be greater than (1<<29)-1.", pbstring.line);
		// deal with inline options
		pbstring = stripLWhite(pbstring);
		if (pbstring[0] == '[') {
			PBOption[]opts = ripOptions(pbstring);
			foreach (opt;opts) if (opt.name == "default") {
				if (child.modifier == "repeated") throw new PBParseException("Default Option("~child.name~" default)","Default options can not be applied to repeated fields.", pbstring.line);
				child.valdefault = opt.value;
			} else if (opt.name == "deprecated" && opt.value == "true") {
				if (child.modifier == "required") throw new PBParseException("Deprecated Option("~child.name~" deprecated)","Deprecated options can not be applied to repeated fields.", pbstring.line);
				child.is_dep = true;
			} else if (opt.name == "packed" && opt.value == "true") {
				if (child.modifier == "required" || child.modifier == "optional") throw new PBParseException("Packed Option("~child.name~" packed)","Packed options can not be applied to "~child.modifier~" fields.", pbstring.line);
				if (child.type == "string" || child.type == "bytes") throw new PBParseException("Packed Option("~child.name~" packed)","Packed options can not be applied to "~child.type~" types.", pbstring.line);
				// applying packed to message types is not properly checked, but is avoided in deser code
				child.packed = true;
			}
		}
		// now, check to see if we have a semicolon so we can be done
		pbstring = stripLWhite(pbstring);
		if (pbstring[0] == ';') {
			// rip off the semicolon
			pbstring = pbstring[1..pbstring.length];
			return child;
		}
		throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","No idea what to do with string after index and options.", pbstring.line);
	}
}

string toDType(string intype) {
        string retstr;
        switch(intype) {
        case "sint32","sfixed32","int32":
                retstr = "int";
                break;
        case "sint64","sfixed64","int64":
                retstr = "long";
                break;
        case "fixed32","uint32":
                retstr = "uint";
                break;
        case "fixed64","uint64":
                retstr = "ulong";
                break;
        case "string":
                retstr = "string";
                break;
        case "bytes":
                retstr = "ubyte[]";
                break;
        default:
                // this takes care of float, double, and bool as well
                retstr = intype;
                break;
        }
        return retstr;
}

unittest {
	writefln("unittest ProtocolBuffer.pbchild");
	// assumes leading whitespace has already been stripped
	auto childtxt = ParserData("optional int32 i32test = 1[default=5];");
	auto child = PBChild(childtxt);
	debug writefln("Checking modifier...");
	assert(child.modifier == "optional");
	debug writefln("Checking type...");
	assert(child.type == "int32");
	debug writefln("Checking name...");
	assert(child.name == "i32test");
	debug writefln("Checking message index...");
	assert(child.index == 1);
	debug writefln("");
}

bool isPackable(string type) {
	ubyte wt = wTFromType(type);
	if (wt == 0 || wt == 1 || wt == 5) {
		return true;
	}
	return false;
}

ubyte wTFromType(string type) {
	switch(type) {
	case "float","sfixed32","fixed32":
		return cast(ubyte)5;
	case "double","sfixed64","fixed64":
		return cast(ubyte)1;
	case "bool","int32","int64","uint32","uint64","sint32","sint64":
		return cast(ubyte)0;
	case "string","bytes":
		return cast(ubyte)2;
	default:
	}
	throw new Exception("Type Classification - Unknown type string: " ~ type);
}
