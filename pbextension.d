// this code implements the ability to extend messages
module ProtocolBuffer.pbextension;
import ProtocolBuffer.pbchild;
import ProtocolBuffer.pbgeneral;
import std.string;
import std.stdio;

struct PBExtension {
	char[]name;
	PBChild[]children;

	// string-modifying constructor
	static PBExtension opCall(inout char[]pbstring)
	in {
		assert(pbstring.length);
	} body {
		// things we currently support in a message: messages, enums, and children(repeated, required, optional)
		// first things first, rip off "message"
		pbstring = pbstring["extend".length..$];
		// now rip off the next set of whitespace
		pbstring = stripLWhite(pbstring);
		// get message name
		char[]name = stripValidChars(CClass.MultiIdentifier,pbstring);
		PBExtension exten;
		exten.name = name;
		// rip off whitespace
		pbstring = stripLWhite(pbstring);
		// make sure the next character is the opening {
		if (pbstring[0] != '{') {
			throw new PBParseException("Message Definition","Expected next character to be '{'. You may have a space in your message name: "~name);
		}
		// rip off opening {
		pbstring = pbstring[1..$];
		// prep for loop spinup by removing extraneous whitespace
		pbstring = stripLWhite(pbstring);
		// now we're ready to enter the loop and parse children
		while(pbstring[0] != '}') {
			// start parsing, we shouldn't have any whitespace here
			exten.children ~= PBChild(pbstring);
			// this needs to stay at the end
			pbstring = stripLWhite(pbstring);
		}
		// rip off the }
		pbstring = pbstring[1..$];
		return exten;
	}
}

unittest {
	char[]instr = 
"extend Foo {
	optional clunker blah = 1;
}
";
	writefln("unittest ProtocolBuffer.pbextension");
	auto exten = PBExtension(instr);
	debug writefln("Checking PBExtension class correctness");
	assert(exten.name == "Foo","Class to be extended is incorrect");
	debug writefln("Checking PBExtension child correctness");
	assert(exten.children[0].name == "blah","Parsed child is incorrect");
	assert(exten.children[0].modifier == "optional","Parsed child is incorrect");
	assert(exten.children[0].type == "clunker","Parsed child is incorrect");
	assert(exten.children[0].index == 1,"Parsed child is incorrect");
	debug writefln("");
}

