// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbchild;
import ProtocolBuffer.pbgeneral;
import std.string;
import std.stdio;

struct PBChild {
	char[]modifier;
	char[]type;
	char[]name;
	int index;
	// this takes care of definition and accessors
	char[]toDString(char[]indent) {
		// XXX need to take care of defaults here once we support options XXX
		char[]ret;
		ret ~= indent~toDType(type)~(modifier=="repeated"?"[]":" ")~name~";\n";
		// get accessor
		ret ~= indent~toDType(type)~(modifier=="repeated"?"[]":" ")~"get_"~name~"() {\n";
		indent ~= "	";
		ret ~= indent~"return "~name~";\n";
		indent = indent[0..$-1];
		ret ~= indent~"}\n";
		// set accessor
		ret ~= indent~"void set_"~name~"("~toDType(type)~(modifier=="repeated"?"[]":" ")~"input_var) {\n";
		indent ~= "	";
		ret ~= indent~name~" = input_var;\n";
		indent = indent[0..$-1];
		ret ~= indent~"}\n";
		return ret;
	}

	static PBChild opCall(inout char[]pbstring)
	in {
		assert(pbstring.length);
	} body {
		PBChild child;
		// all of the modifiers happen to be the same length...whodathunkit
		// also, it's guaranteed to be there by previous code, so it shouldn't need error checking
		child.modifier = pbstring[0.."repeated".length];
		pbstring = pbstring["repeated".length..$];
		pbstring = stripLWhite(pbstring);
		// now we want to pull out the type
		child.type = stripValidChars(CClass.MultiIdentifier,pbstring);
		if (!child.type.length) throw new PBParseException("Child Instantiation","Could not pull type from definition.");
		if (!validateMultiIdentifier(child.type)) throw new PBParseException("Child Instantiation","Invalid type identifier "~child.type~".");
		pbstring = stripLWhite(pbstring);
		// pull out the name of the instance, now
		child.name = stripValidChars(CClass.Identifier,pbstring);
		if (!child.name.length) throw new PBParseException("Child Instantiation("~child.type~")","Could not pull name from definition.");
		if (!validIdentifier(child.name)) throw new PBParseException("Child Instantiation("~child.type~")","Invalid name identifier "~child.name~".");
		pbstring = stripLWhite(pbstring);
		// make sure the next character is =, because we need to snag the index, next
		if (pbstring[0] != '=') throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Missing '=' for child instantiation.");
		pbstring = pbstring[1..$];
		pbstring = stripLWhite(pbstring);
		// pull numeric index
		char[]tmp = stripValidChars(CClass.Numeric,pbstring);
		if (!tmp.length) throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Could not pull numeric index.");
		child.index = cast(int)atoi(tmp);
		if (child.index <= 0) throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Numeric index can not be less than 1.");
		if (child.index > 15) throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Numeric index can not be greater than 15.");
		pbstring = stripLWhite(pbstring);
		// now, check to see if we have a semicolon so we can be done
		if (pbstring[0] == ';') {
			// rip off the semicolon
			pbstring = pbstring[1..$];
			return child;
		}
		// we're still here, so there may be options in []
		if (pbstring[0] != '[') throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","No idea what to do with string after index.");
		// XXX support options! XXX
		throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Options are not currently supported.");
	}

	char[]genSerLine(char[]indent) {
		char[]tname = name;
		char[]ret;
		if (modifier == "repeated") {
			ret ~= indent~"foreach(iter;"~name~") {\n";
			tname = "iter";
			indent ~= "	";
		}
		switch(type) {
		case "float","double","sfixed32","sfixed64","fixed32","fixed64":
			ret ~= indent~"ret ~= toByteBlob("~tname~",cast(byte)"~toString(index)~");\n";
			break;
		case "bool","int32","int64","uint32","uint64":
			ret ~= indent~"ret ~= toVarint("~tname~",cast(byte)"~toString(index)~");\n";
			break;
		case "sint32","sint64":
			ret ~= indent~"ret ~= toSInt("~tname~",cast(byte)"~toString(index)~");\n";
			break;
		case "string","bytes":
			ret ~= indent~"ret ~= toByteString("~tname~",cast(byte)"~toString(index)~");\n";
			break;
		default:
			// this covers defined messages and enums
			ret ~= indent~"static if (is("~type~":Object)) {\n";
			ret ~= indent~"	ret ~= "~tname~".Serialize(cast(byte)"~toString(index)~");\n";
			ret ~= indent~"} else {\n";
			ret ~= indent~"	// this is an enum, almost certainly\n";
			ret ~= indent~"	ret ~= toVarint!(int)("~tname~",cast(byte)"~toString(index)~");\n";
			ret ~= indent~"}\n";
			break;
		}
		if (modifier == "repeated") {
			indent = indent[0..$-1];
			ret ~= indent~"}\n";
		}
		return ret;
	}

	char[]genDesLine(char[]indent) {
		char[]ret;
		// check header byte with case since we're guaranteed to be in a switch
		ret ~= indent~"case "~toString(index)~":\n";
		indent ~= "	";
		// common code!
		ret ~= indent~"retobj."~name~" "~(modifier=="repeated"?"~":"")~"= ";
		switch(type) {
		case "float","double","sfixed32","sfixed64","fixed32","fixed64":
			ret ~= "fromByteBlob!("~toDType(type)~")(input);\n";
			break;
		case "bool","int32","int64","uint32","uint64":
			ret ~= "fromVarint!("~toDType(type)~")(input);\n";
			break;
		case "sint32","sint64":
			ret ~= "fromSInt!("~toDType(type)~")(input);\n";
			break;
		case "string","bytes":
			ret ~= "fromByteString!("~toDType(type)~")(input);\n";
			break;
		default:
			// this covers enums and classen, since enums are declared as classes
			// also, make sure we don't think we're root
			ret = indent~"case "~toString(index)~":\n";
			ret ~= indent~"static if (is("~type~":Object)) {\n";
			ret ~= indent~"	retobj."~name~" = "~type~".Deserialize(input,false);\n";
			ret ~= indent~"} else {\n";
			ret ~= indent~"	// this is an enum, almost certainly\n";
			ret ~= indent~"	retobj."~name~" = fromVarint!(int)(input);\n";
			ret ~= indent~"}\n";
			break;
		}
		if (modifier == "required") {
			ret ~= indent~"_"~name~"_check = true;\n";
		}
		// tack on the break so we don't have fallthrough
		ret ~= indent~"break;\n";
		return ret;
	}
}

char[]toDType(char[]intype) {
        char[]retstr;
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
                retstr = "char[]";
                break;
        case "bytes":
                retstr = "byte[]";
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
	char[]childtxt = "optional int32 i32test = 1;";
	auto child = PBChild(childtxt);
	debug writefln("Checking modifier...");
	assert(child.modifier == "optional");
	debug writefln("Checking type...");
	assert(child.type == "int32");
	debug writefln("Checking name...");
	assert(child.name == "i32test");
	debug writefln("Checking message index...");
	assert(child.index == 1);
	debug writefln("Checking output...");
	debug writefln("%s",child.toDString("	"));
	childtxt = 
"	int i32test;
	int get_i32test() {
		return i32test;
	}
	void set_i32test(int input_var) {
		i32test = input_var;
	}
";
	assert(child.toDString("	") == childtxt);
	debug writefln("");
}

