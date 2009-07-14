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
	char[]toDString(char[]indent) {
		// XXX need to take care of defaults here once we support options XXX
		return indent~toDType(type)~" "~name~";\n";
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
		switch(type) {
		case "float","double","sfixed32","sfixed64","fixed32","fixed64":
			return indent~"ret ~= toByteBlob("~name~",cast(byte)"~toString(index)~");\n";
		case "bool","int32","int64","uint32","uint64":
			return indent~"ret ~= toVarint("~name~",cast(byte)"~toString(index)~");\n";
		case "sint32","sint64":
			return indent~"ret ~= toSInt("~name~",cast(byte)"~toString(index)~");\n";
		case "string","bytes":
			return indent~"ret ~= toByteString("~name~",cast(byte)"~toString(index)~");\n";
		default:
			// this covers defined messages and enums
			// XXX add a static if in the generated code to determine whether a class or enum and act appropriately
			return indent~"ret ~= "~name~".Serialize(cast(byte)"~toString(index)~");\n";
		}
		throw new PBParseException("genSerLine("~name~")","Fell through switch.");
	}

	char[]genDesLine(char[]indent) {
		char[]ret;
		// check header byte with case since we're guaranteed to be in a switch
		ret ~= indent~"case "~toString(index)~":\n";
		indent ~= "	";
		// common code!
		ret ~= indent~"retobj."~name~" = ";
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
			// XXX add a static if in the generated code to determine whether a class or enum and act appropriately
			// also, make sure we don't think we're root
			ret ~= type~".Deserialize(input,false);\n";
			break;
		}
		return ret;
	}

	char[]genAccessor(char[]indent) {
		char[]ret;
		// get accessor
		ret ~= indent~toDType(type)~" get_"~name~"() {\n";
		indent ~= "	";
		ret ~= indent~"return "~name~";\n";
		indent = indent[0..$-1];
		ret ~= indent~"}\n";
		// set accessor
		ret ~= indent~"void set_"~name~"("~toDType(type)~" input_var) {\n";
		indent ~= "	";
		ret ~= indent~name~" = input_var;\n";
		indent = indent[0..$-1];
		ret ~= indent~"}\n";
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
	assert(child.toDString("	") == "	int i32test;\n");
	debug writefln("");
}

