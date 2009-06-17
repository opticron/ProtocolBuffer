// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbchild;
import ProtocolBuffer.pbgeneral;
import std.string;
import std.stdio;

// XXX I intentionally left out all identifier validation routines, because the compiler knows how to resolve symbols. XXX
// XXX This means I don't have to write that code. XXX

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
		child.index = atoi(tmp);
		if (child.index == 0) throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Numeric index can not be 0.");
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
		return child;
	}
}

char[]toDType(char[]intype) {
        // XXX fix types here XXX
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
        case "string","bytes":
                retstr = "char[]";
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
	writefln("Checking modifier...");
	assert(child.modifier == "optional");
	writefln("Checking type...");
	assert(child.type == "int32");
	writefln("Checking name...");
	assert(child.name == "i32test");
	writefln("Checking message index...");
	assert(child.index == 1);
	writefln("Checking output...");
	debug writefln("%s",child.toDString("	"));
	assert(child.toDString("	") == "	int i32test;\n");
	return 0;
}

