// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbgeneral;
import std.string;
import std.stdio;

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
	case "enum":
		return PBTypes.PB_Enum;
	case "message":
		return PBTypes.PB_Message;
	case "repeated":
		return PBTypes.PB_Repeated;
	case "required":
		return PBTypes.PB_Required;
	case "optional":
		return PBTypes.PB_Optional;
	case "option":
	case "extension":
	case "extend":
	case "service":
	case "import":
		throw new PBParseException("Protocol Buffer Definition",capitalize(type)~" definitions are not currently supported.");
	default:
		throw new PBParseException("Protocol Buffer Definition","Unknown element type "~type~".");
	}
	throw new PBParseException("Protocol Buffer Definition","Element type "~type~" fell through the switch.");
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
	case CClass.Comment:
		if (pc == '\n') return false;
		if (pc == '\r') return false;
		if (pc == '\f') return false;
		return true;
	default:
		throw new PBParseException("Name Validation","Cannot validate characters for this PBType name.");
	}
	throw new PBParseException("Name Validation","PBType fell through the switch.");
}

bool validIdentifier(char[]ident)
in {
	assert(ident.length);
} body {
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
	debug writefln("Checking stripLWhite...");
	assert("asdf " == stripLWhite("  \n	asdf "));
	debug writefln("Checking validIdentifier...");
	assert(validIdentifier("asdf"));
	assert(!validIdentifier("8asdf"));
	// also takes care of isValidChar
	debug writefln("Checking stripValidChars...");
	char[]tmp = "asdf1 yarrr";
	assert(stripValidChars(CClass.Identifier,tmp) == "asdf1");
	assert(tmp == " yarrr");
	tmp = "as2f.ya7rr -adfbads25737";
	assert(stripValidChars(CClass.MultiIdentifier,tmp) == "as2f.ya7rr");
	assert(tmp == " -adfbads25737");
	assert("asdf" == stripLWhite("  	asdf"));
	debug writefln("");
}

struct PBOption {
	char[]name;
	char[]subident;
	char[]value;
	bool extension = false;
}

// XXX actually do something with options
PBOption ripOption(inout char[]pbstring,char terminator = ';') {
	// we need to pull apart the option and stuff it in a struct
	PBOption pbopt;
	if (pbstring[0] == '(') {
		stripLWhite(pbstring);
		pbopt.extension = true;
		pbstring = pbstring[1..$];
	}
	pbstring = stripLWhite(pbstring);
	pbopt.name = stripValidChars(CClass.MultiIdentifier,pbstring);
	if (!pbopt.name.length) throw new PBParseException("Option Parse","Malformed option: Option name not found.");
	if (pbopt.extension) {
		pbstring = stripLWhite(pbstring);
		// rip off trailing )
		pbstring = pbstring[1..$];
		// check for more portions of the identifier
		if (pbstring[0] == '.') {
			// rip off the leading .
			pbstring = pbstring[1..$];
			// rip the continuation of the identifier
			pbopt.name = stripValidChars(CClass.MultiIdentifier,pbstring);
		}
	}
	pbstring = stripLWhite(pbstring);
	// expect next char must be =
	if (pbstring[0] != '=') throw new PBParseException("Option Parse("~pbopt.name~")","Malformed option: Missing = after option name.");
	pbstring = pbstring[1..$];
	pbstring = stripLWhite(pbstring);
	// the remaining text between here and the terminator is our value
	// XXX this string pulling code is buggy
	char tmpterm = terminator;
	if (pbstring[0] == '"') {
		pbstring = pbstring[1..$];
		tmpterm = '"';
	}
	int valend = pbstring.find(tmpterm);
	if (valend == -1) {
		throw new PBParseException("Option Parse("~pbopt.name~")","Malformed option: Missing terminator("~tmpterm~")");
	}
	pbopt.value = pbstring[0..valend];
	// we know the terminator is there, so rip it off
	pbstring = pbstring[valend+1..$];
	if (tmpterm == '"') {
		// make sure the real terminator is there
		if (pbstring[0] != terminator) throw new PBParseException("Option Parse("~pbopt.name~")","Malformed option: Missing terminator("~terminator~")");
		// rip off the real terminator
		pbstring = pbstring[1..$];
	}
	return pbopt;
}

