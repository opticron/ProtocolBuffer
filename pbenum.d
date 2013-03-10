// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbenum;
import ProtocolBuffer.pbgeneral;
import std.conv;
import std.stdio;
import std.string;
version(unittest) import std.regex;

struct PBEnum {
	string name;
	string[int] values;
	string toDString(string indent) {
		string retstr = "";
		retstr ~= indent~"enum "~name~" {\n";
		foreach (key,value;values) {
			retstr ~= indent~"	"~value~" = "~to!string(key)~",\n";
		}
		retstr ~= indent~"}\n";
		return retstr;
	}

	// string-modifying constructor
	static PBEnum opCall(ref ParserData pbstring)
	in {
		assert(pbstring.length);
	} body {
		PBEnum pbenum;
		// strip of "enum" and following whitespace
		pbstring = pbstring["enum".length..$];
		pbstring = stripLWhite(pbstring);
		// grab name
		pbenum.name = stripValidChars(CClass.Identifier,pbstring);
		if (!pbenum.name.length) throw new PBParseException("Enum Definition","Could not pull name from definition.", pbstring.line);
		if (!validIdentifier(pbenum.name)) throw new PBParseException("Enum Definition","Invalid name identifier "~pbenum.name~".", pbstring.line);
		pbstring = stripLWhite(pbstring);
		// make sure the next character is the opening {
		if (pbstring[0] != '{') {
			throw new PBParseException("Enum Definition("~pbenum.name~")","Expected next character to be '{'. You may have a space in your enum name: "~pbenum.name, pbstring.line);
		}
		// rip off opening {
		pbstring = pbstring[1..$];
		// now we're ready to enter the loop and parse children
		while(pbstring[0] != '}') {
			pbstring = stripLWhite(pbstring);
			if (pbstring.length>1 && pbstring[0..2] == "//") {
				// rip out the comment...
				stripValidChars(CClass.Comment,pbstring);
			} else {
				// start parsing, we shouldn't have any whitespace here
				pbenum.grabEnumValue(pbstring);
			}
		}
		// rip off the }
		pbstring = pbstring[1..$];
		return pbenum;
	}

	void grabEnumValue(ref ParserData pbstring)
	in {
		assert(pbstring.length);
	} body {
		// whitespace has already been ripped
		// snag item name
		string tmp = stripValidChars(CClass.Identifier,pbstring);
		if (!tmp.length) throw new PBParseException("Enum Definition("~name~")","Could not pull item name from definition.", pbstring.line);
		if (!validIdentifier(tmp)) throw new PBParseException("Enum Definition("~name~")","Invalid item name identifier "~tmp~".", pbstring.line);
		// check for options
		if (tmp == "option") {
			writefln("Ignoring option");
			ripOption(pbstring);
			return;
		}
		pbstring = stripLWhite(pbstring);
		// ensure that the name doesn't already exist
		foreach(val;values.values) if (tmp == val) throw new PBParseException("Enum Definition("~name~")","Multiply defined element("~tmp~")", pbstring.line);
		// make sure to traverse the '='
		if (pbstring[0] != '=') throw new PBParseException("Enum Definition("~name~"."~tmp~")","Expected '=', but got something else. You may have a space in one of your enum items.", pbstring.line);
		pbstring = pbstring[1..$];
		pbstring = stripLWhite(pbstring);
		// now parse a numeric
		string num = stripValidChars(CClass.Numeric,pbstring);
		if (!num.length) throw new PBParseException("Enum Definition("~name~"."~tmp~")","Could not pull numeric enum value.", pbstring.line);
		values[to!int(num)] = tmp;
		pbstring = stripLWhite(pbstring);
		// deal with inline options
		if (pbstring[0] == '[') {
			ripOptions(pbstring);
		}
		// make sure we snatch a semicolon
		if (pbstring[0] == ';') {
			// we're done here
			pbstring = pbstring[1..$];
			return;
		}
		throw new PBParseException("Enum Definition("~name~"."~tmp~"="~num~")","Expected ';'.", pbstring.line);
	}
}

unittest {
	writefln("unittest ProtocolBuffer.pbenum");
	// the leading whitespace is assumed to already have been stripped
	auto estring = ParserData("enum potato {TOTALS = 1;JUNK= 5 ; ALL =3;}");
	auto edstring = PBEnum(estring).toDString("");
	debug writefln("%s",edstring);
    assert(edstring.match(regex(r"TOTALS = 1")).empty == false);
    assert(edstring.match(regex(r"ALL = 3")).empty == false);
    assert(edstring.match(regex(r"JUNK = 5")).empty == false);
	debug writefln("");
}

