// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbgeneral;
import std.string;
import std.stdio;

// XXX I intentionally left out all identifier validation routines, because the compiler knows how to resolve symbols. XXX
// XXX This means I don't have to write that code. XXX

enum PBTypes {
	PB_Package=1,
	PB_Enum,
	PB_Message,
	PB_Option,
	PB_Extension,
	PB_Extend,
	PB_Service,
	PB_Import,
	PB_Optional,
	PB_Required,
	PB_Repeated,
	PB_Comment,
}

// character classes for parsing
enum CClass {
	MultiIdentifier,
	Identifier,
	Numeric,
	Comment,
}

bool validateMultiIdentifier(char[]ident)
in {
	assert(ident.length);
} body {
	// XXX assuming that the identifier can't start or end with . and individual parts can't start with numerics XXX
	char[][]parts = split(ident,".");
	foreach(part;parts) {
		if (!part.length) return false;
		if (!validIdentifier(part)) return false;
	}
	return true;
}

class PBParseException:Exception {
	char[]locus;
	char[]error;
	this(char[]location,char[]problem) {
		locus = location;
		error = problem;
		super(locus~": "~error);
	}
}


PBTypes typeNextElement(in char[]pbstring)
in {
	assert(pbstring.length);
} body {
	// we want to check for // type comments here, since there doesn't necessarily have to be a space after the opener
	if (pbstring.length>1 && pbstring[0..2] == "//") return PBTypes.PB_Comment;
	int i=0;
	for(;i<pbstring.length && !iswhite(pbstring[i]);i++){}
	auto type = pbstring[0..i];
	switch(type) {
	case "package":
		return PBTypes.PB_Package;
		break;
	case "enum":
		return PBTypes.PB_Enum;
		break;
	case "message":
		return PBTypes.PB_Message;
		break;
	case "repeated":
		return PBTypes.PB_Repeated;
		break;
	case "required":
		return PBTypes.PB_Required;
		break;
	case "optional":
		return PBTypes.PB_Optional;
		break;
	case "option":
	case "extension":
	case "extend":
	case "service":
	case "import":
		throw new PBParseException("Protocol Buffer Definition",capitalize(type)~" definitions are not currently supported.");
		break;
	default:
		throw new PBParseException("Protocol Buffer Definition","Unknown element type "~type~".");
		break;
	}
}

// this will rip off the next token
char[]stripValidChars(CClass cc,inout char[]pbstring)
in {
	assert(pbstring.length);
} body {
	int i=0;
	for(;i<pbstring.length && isValidChar(cc,pbstring[i]);i++){}
	char[]tmp = pbstring[0..i];
	pbstring = pbstring[i..$];
	return tmp;
}

// allowed characters vary by type
bool isValidChar(CClass cc,char pc) {
	switch(cc) {
	case CClass.MultiIdentifier:
	case CClass.Identifier:
		if (pc >= 'a' && pc <= 'z') return true;
		if (pc >= 'A' && pc <= 'Z') return true;
		if (pc == '.' && cc == CClass.MultiIdentifier) return true;
	case CClass.Numeric:
		if (pc >= '0' && pc <= '9') return true;
		return false;
		break;
	case CClass.Comment:
		if (pc == '\n') return false;
		if (pc == '\r') return false;
		if (pc == '\f') return false;
		return true;
		break;
	default:
		throw new PBParseException("Name Validation","Cannot validate characters for this PBType name.");
	}
}

bool validIdentifier(char[]ident)
in {
	assert(ident.length);
} body {
	// XXX for now, we assume that the identifier was pulled using the stripvalidchars function, so we only have to check the first character XXX
	if (ident[0] >= '0' && ident[0] <= '9') return false;
	return true;
}

char[] stripLWhite(char[] s)
in {
	assert(s.length);
} body {
    size_t i;

    for (i = 0; i < s.length; i++)
    {
        if (!iswhite(s[i]))
            break;
    }
    return s[i .. s.length];
}

unittest {
	writefln("unittest ProtocolBuffer.pbgeneral");
	writefln("Checking stripLWhite...");
	assert("asdf " == stripLWhite("  \n	asdf "));
	writefln("Checking validIdentifier...");
	assert(validIdentifier("asdf"));
	assert(!validIdentifier("8asdf"));
	writefln("Checking stripValidChars...");
	char[]tmp = "asdf1 yarrr";
	assert(stripValidChars(CClass.Identifier,tmp) == "asdf1");
	assert(tmp == " yarrr");
	tmp = "as2f.ya7rr -adfbads25737";
	assert(stripValidChars(CClass.MultiIdentifier,tmp) == "as2f.ya7rr");
	assert(tmp == " -adfbads25737");
	// XXX these need to be finished up for all functions XXX
	return 0;
}

