// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbgeneral;
version(D_Version2) {
	import std.algorithm;
	import std.range;
} else
	import ProtocolBuffer.pbhelper;

import std.stdio;
import std.string;
import std.uni;
import std.conv;

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
	Value,
}

bool validateMultiIdentifier(string ident)
in {
	assert(ident.length);
} body {
	string[] parts = split(ident,".");
	foreach(part;parts) {
		if (!part.length) return false;
		if (!validIdentifier(part)) return false;
	}
	return true;
}

class PBParseException:Exception {
	string locus;
	string error;
	size_t lineNumber;
	this(string location,string problem, size_t inputLine, string file = __FILE__, size_t line = __LINE__) {
		version(D_Version2) {
			super(location~": "~problem~" Line:"~to!(string)(inputLine), file, line);
		} else {
			super(location~": "~problem~" Line:"~to!(string)(inputLine));
		}

		locus = location;
		error = problem;
		lineNumber = inputLine;
	}
}

struct ParserData {
	string input;
	size_t line = 1;

	version(D_Version2) {
		mixin("alias input this;");
	} else {
		size_t length() {
			return input.length;
		}

		ParserData opSlice(size_t left, size_t right) {
			return ParserData(input[left..right], line);
		}

		size_t opDollar() {
			return input.length;
		}

		char opIndex(size_t i) {
			return input[i];
		}
	}
}

struct CommentManager {
	string[] comments;
	size_t line;
	size_t lastElementLine;
	PBTypes lastElementType;

	version(D_Version2) {
		mixin("alias comments this;");
	} else {
		void opCatAssign(string v) {
			comments ~= v;
		}
	}
}

PBTypes typeNextElement(in ParserData pbstring)
in {
	assert(pbstring.length);
} body {
	// we want to check for // type comments here, since there doesn't necessarily have to be a space after the opener
	if (pbstring.length>1 && pbstring.input[0..2] == "//") return PBTypes.PB_Comment;
	int i=0;
	version(D_Version2)
		for(;i<pbstring.length && !isWhite(pbstring[i]);i++){}
	else
		for(;i<pbstring.length && !iswhite(pbstring[i]);i++){}
	auto type = pbstring.input[0..i];
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
		return PBTypes.PB_Option;
	case "import":
		return PBTypes.PB_Import;
	case "extensions":
		return PBTypes.PB_Extension;
	case "extend":
		return PBTypes.PB_Extend;
	case "service":
		throw new PBParseException("Protocol Buffer Definition",capitalize(type)~" definitions are not currently supported.", pbstring.line);
	default:
		throw new PBParseException("Protocol Buffer Definition","Unknown element type "~type~".", pbstring.line);
	}
	throw new PBParseException("Protocol Buffer Definition","Element type "~type~" fell through the switch.", pbstring.line);
}

// this will rip off the next token
string stripValidChars(CClass cc,ref ParserData pbstring)
in {
	assert(pbstring.length);
} body {
	if(pbstring[0] == '_' || pbstring.input[$-1] == '_')
		throw new PBParseException("Next Token","Identifier cannot begin or end with underscore", pbstring.line);
	int i=0;
	for(;i<pbstring.length && isValidChar(cc,pbstring[i]);i++){}
	string tmp = pbstring.input[0..i];
	pbstring = pbstring[i..pbstring.length];
	return tmp;
}

unittest {
	auto str = ParserData("// Filly\n");
	assert(stripValidChars(CClass.Comment, str) == "// Filly");
	assert(str.input == "\n");
}


// allowed characters vary by type
bool isValidChar(CClass cc,char pc) {
	switch(cc) {
	case CClass.Value:
		if (pc == '-') return true;
	case CClass.MultiIdentifier:
		if (pc == '.') return true;
	case CClass.Identifier:
		if (pc >= 'a' && pc <= 'z') return true;
		if (pc >= 'A' && pc <= 'Z') return true;
		if (pc == '_') return true;
	case CClass.Numeric:
		if (pc >= '0' && pc <= '9') return true;
		return false;
	case CClass.Comment:
		if (pc == '\n') return false;
		if (pc == '\r') return false;
		if (pc == '\f') return false;
		return true;
	default:
		assert(false, "Missing switch case");
	}
}

bool validIdentifier(string ident)
in {
	assert(ident.length);
} body {
	if (ident[0] >= '0' && ident[0] <= '9') return false;
	return true;
}

ParserData stripLWhite(ParserData s)
in {
	assert(s.length);
} body {
	size_t i;

	for (i = 0; i < s.length; i++)
	{
		version(D_Version2) {
			if (!isWhite(s[i]))
				break;
		} else {
			if (!iswhite(s[i]))
				break;
		}
		if (s[i] == '\n')
			s.line++;
		if (s[i] == '\r') {
			s.line++;
			if(s.length < i+1 && s[i+1] == '\n')
				i++;
		}
	}
	s.input = s.input[i .. $];
	return s;
}
unittest {
	assert("asdf " == stripLWhite(ParserData("  \n\tasdf ")).input);
	assert(stripLWhite(ParserData("  \n\tasdf ")).line == 2);
	assert("asdf" == stripLWhite(ParserData("  \tasdf")).input);
}

unittest {
	writefln("unittest ProtocolBuffer.pbgeneral");
	debug writefln("Checking validIdentifier...");
	assert(validIdentifier("asdf"));
	assert(!validIdentifier("8asdf"));
	// also takes care of isValidChar
	debug writefln("Checking stripValidChars...");
	auto tmp = ParserData("asdf1 yarrr");
	assert(stripValidChars(CClass.Identifier,tmp) == "asdf1");
	assert(tmp.input == " yarrr");
	tmp = ParserData("as2f.ya7rr -adfbads25737");
	assert(stripValidChars(CClass.MultiIdentifier,tmp) == "as2f.ya7rr");
	assert(tmp.input == " -adfbads25737");
	debug writefln("");
}

struct PBOption {
	string name;
	string subident;
	string value;
	bool extension = false;
}

// TODO: actually do something with options
PBOption ripOption(ref ParserData pbstring,string terms = ";") {
	// we need to pull apart the option and stuff it in a struct
	PBOption pbopt;
	if (pbstring[0] == '(') {
		stripLWhite(pbstring);
		pbopt.extension = true;
		pbstring = pbstring[1..pbstring.length];
	}
	pbstring = stripLWhite(pbstring);
	pbopt.name = stripValidChars(CClass.MultiIdentifier,pbstring);
	if (!pbopt.name.length) throw new PBParseException("Option Parse","Malformed option: Option name not found.", pbstring.line);
	if (pbopt.extension) {
		pbstring = stripLWhite(pbstring);
		// rip off trailing )
		pbstring = pbstring[1..pbstring.length];
		// check for more portions of the identifier
		if (pbstring[0] == '.') {
			// rip off the leading .
			pbstring = pbstring[1..pbstring.length];
			// rip the continuation of the identifier
			pbopt.name = stripValidChars(CClass.MultiIdentifier,pbstring);
		}
	}
	pbstring = stripLWhite(pbstring);
	// expect next char must be =
	if (!pbstring.input.skipOver("=")) throw new PBParseException("Option Parse("~pbopt.name~")","Malformed option: Missing = after option name.", pbstring.line);
	pbstring = stripLWhite(pbstring);
	// the remaining text between here and the terminator is our value
	if (pbstring[0] == '"') {
		pbopt.value = ripQuotedValue(pbstring);
		pbstring = stripLWhite(pbstring);
		version(D_Version2) {
			if (terms.find(pbstring[0]).empty) throw new PBParseException("Option Parse("~pbopt.name~")","Malformed option: Bad terminator("~pbstring[0]~")", pbstring.line);
		} else
			if (terms.find(pbstring[0]) == -1) throw new PBParseException("Option Parse("~pbopt.name~")","Malformed option: Bad terminator("~pbstring[0]~")", pbstring.line);
		// leave the terminator in the string in case the caller wants to look at it
		return pbopt;
	}
	// take care of non-quoted values
	pbopt.value = stripValidChars(CClass.Value,pbstring);
	pbstring = stripLWhite(pbstring);
	version(D_Version2) {
		if (terms.find(pbstring[0]).empty) throw new PBParseException("Option Parse("~pbopt.name~")","Malformed option: Bad terminator("~pbstring[0]~")", pbstring.line);
	} else
		if (terms.find(pbstring[0]) == -1) throw new PBParseException("Option Parse("~pbopt.name~")","Malformed option: Bad terminator("~pbstring[0]~")", pbstring.line);
	return pbopt;
}

unittest {
	auto str = ParserData("java_package = \"Fish\";");
	auto pbopt = ripOption(str);
	assert(pbopt.name == "java_package");
	assert(pbopt.value == "\"Fish\"");

	str = ParserData("java_multiple_files = true;");
	pbopt = ripOption(str);
	assert(pbopt.name == "java_multiple_files");
	assert(pbopt.value == "true");

	str = ParserData("java_generate_equals_and_hash = true;");
	pbopt = ripOption(str);
	assert(pbopt.name == "java_generate_equals_and_hash");
	assert(pbopt.value == "true");

	str = ParserData("optimize_for = LITE_RUNTIME;");
	pbopt = ripOption(str);
	assert(pbopt.name == "optimize_for");
	assert(pbopt.value == "LITE_RUNTIME");

	str = ParserData("default = -1];");
	pbopt = ripOption(str, "]");
	assert(pbopt.name == "default");
	assert(pbopt.value == "-1");
	assert(str.input[0] == ']'); // option blocks may term with comma
}

string ripQuotedValue(ref ParserData pbstring) {
	int x;
	for(x = 1;pbstring[x] != '"' && x < pbstring.length;x++) {
		if(pbstring[x] == '\n')
			pbstring.line++;
		if(pbstring[x] == '\r') {
			pbstring.line++;
			if(pbstring.length < x+1 && pbstring[x+1] == '\n')
				x++;
		}
	}
	// inc to take the quotes with us
	x++;
	string tmp = pbstring.input[0..x];
	pbstring = pbstring[x..pbstring.length];
	return tmp;
}

// this rips line-specific options from the string
PBOption[]ripOptions(ref ParserData pbstring) {
	PBOption[]ret;
	while(pbstring.length && pbstring[0] != ']') {
		// this will rip off the leading [ and intermediary ','s
		pbstring = pbstring[1..pbstring.length];
		ret ~= ripOption(pbstring,",]");
		debug writefln("Pulled option %s with value %s",ret[$-1].name,ret[$-1].value);
	}
	// rip off the trailing ]
	pbstring.input.skipOver("]");
	return ret;
}
