// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbenum;
import ProtocolBuffer.pbgeneral;

version(D_Version2) {
	import std.algorithm;
	import std.range;
	import std.regex;
} else
	import ProtocolBuffer.pbhelper;

import std.conv;
import std.stdio;
import std.string;

struct PBEnum {
	string name;
	string[] comments;
	string[][int] valueComments;
	string[int] values;

	// string-modifying constructor
	static PBEnum opCall(ref ParserData pbstring)
	in {
		assert(pbstring.length);
	} body {
		PBEnum pbenum;
		// strip of "enum" and following whitespace
		pbstring = pbstring["enum".length..pbstring.length];
		pbstring = stripLWhite(pbstring);
		// grab name
		pbenum.name = stripValidChars(CClass.Identifier,pbstring);
		if (!pbenum.name.length) throw new PBParseException("Enum Definition","Could not pull name from definition.", pbstring.line);
		if (!validIdentifier(pbenum.name)) throw new PBParseException("Enum Definition","Invalid name identifier "~pbenum.name~".", pbstring.line);
		pbstring = stripLWhite(pbstring);

		// rip out the comment...
		if (pbstring.length>1 && pbstring.input[0..2] == "//") {
			pbenum.comments ~= stripValidChars(CClass.Comment,pbstring);
			pbstring = stripLWhite(pbstring);
		}

		// make sure the next character is the opening {
		if (!pbstring.input.skipOver("{")) {
			throw new PBParseException("Enum Definition("~pbenum.name~")","Expected next character to be '{'. You may have a space in your enum name: "~pbenum.name, pbstring.line);
		}

		CommentManager storeComment;
		int elementNum;

		pbstring = stripLWhite(pbstring);
		// now we're ready to enter the loop and parse children
		while(pbstring[0] != '}') {
			if (pbstring.input.skipOver("option")) {
				pbstring = stripLWhite(pbstring);
				writefln("Ignoring option %s",
				ripOption(pbstring).name);
				pbstring.input.skipOver(";");
			}
			else if (pbstring.length>1 && pbstring.input[0..2] == "//") {
				// rip out the comment...
				storeComment ~= stripValidChars(CClass.Comment,pbstring);
				storeComment.line = pbstring.line;
			} else {
				// start parsing, we shouldn't have any whitespace here
				elementNum = pbenum.grabEnumValue(pbstring);
				storeComment.lastElementLine = pbstring.line;
				if(!storeComment.comments.empty()) {
					pbenum.valueComments[elementNum] = storeComment.comments;
					storeComment.comments = null;
				}
			}
			if(storeComment.line == storeComment.lastElementLine) {
				pbenum.valueComments[elementNum] = storeComment.comments;
				storeComment.comments = null;
			}
			pbstring = stripLWhite(pbstring);
		}
		// rip off the }
		pbstring = pbstring[1..pbstring.length];
		return pbenum;
	}

	/**
	 * returns:
	 *     enum entry value
	 */
	int grabEnumValue(ref ParserData pbstring)
	in {
		assert(pbstring.length);
	} body {
		// whitespace has already been ripped
		// snag item name
		string tmp = stripValidChars(CClass.Identifier,pbstring);
		if (!tmp.length) throw new PBParseException("Enum Definition("~name~")","Could not pull item name from definition.", pbstring.line);
		if (!validIdentifier(tmp)) throw new PBParseException("Enum Definition("~name~")","Invalid item name identifier "~tmp~".", pbstring.line);
		pbstring = stripLWhite(pbstring);
		// ensure that the name doesn't already exist
		foreach(val;values.values) if (tmp == val) throw new PBParseException("Enum Definition("~name~")","Multiple defined element("~tmp~")", pbstring.line);
		// make sure to traverse the '='
		if (!pbstring.input.skipOver("=")) throw new PBParseException("Enum Definition("~name~"."~tmp~")","Expected '=', but got something else. You may have a space in one of your enum items.", pbstring.line);

		pbstring = stripLWhite(pbstring);
		// now parse a numeric
		string num = stripValidChars(CClass.Numeric,pbstring);
		if (!num.length) throw new PBParseException("Enum Definition("~name~"."~tmp~")","Could not pull numeric enum value.", pbstring.line);
		values[to!(int)(num)] = tmp;
		pbstring = stripLWhite(pbstring);
		// deal with inline options
		if (pbstring[0] == '[') {
			ripOptions(pbstring);
		}
		// make sure we snatch a semicolon
		if (!pbstring.input.skipOver(";"))
			throw new PBParseException("Enum Definition("~name~"."~tmp~"="~num~")","Expected ';'.", pbstring.line);

		return to!(int)(num);
	}
}
