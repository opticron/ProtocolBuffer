// this code implements the ability to extend messages
module dprotobuf.pbextension;
import dprotobuf.pbchild;
import dprotobuf.pbgeneral;
import std.string;
import std.stdio;

struct PBExtension {
	string name;
	PBChild[]children;

	// string-modifying constructor
	static PBExtension opCall(ref ParserData pbstring)
	in {
		assert(pbstring.length);
	} body {
		// things we currently support in a message: messages, enums, and children(repeated, required, optional)
		// first things first, rip off "message"
		pbstring = pbstring["extend".length..pbstring.length];
		// now rip off the next set of whitespace
		pbstring = stripLWhite(pbstring);
		// get message name
		string name = stripValidChars(CClass.MultiIdentifier,pbstring);
		PBExtension exten;
		exten.name = name;
		// rip off whitespace
		pbstring = stripLWhite(pbstring);
		// make sure the next character is the opening {
		if (pbstring[0] != '{') {
			throw new PBParseException("Message Definition","Expected next character to be '{'. You may have a space in your message name: "~name, pbstring.line);
		}
		// rip off opening {
		pbstring = pbstring[1..pbstring.length];
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
		pbstring = pbstring[1..pbstring.length];
		return exten;
	}
}

unittest {
	auto instr =
ParserData("extend Foo {
	optional clunker blah = 1;
}
");
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

import dprotobuf.pbmessage;
auto insertExtension(PBMessage pbmsg, PBExtension ext) {
	assert(pbmsg.name == ext.name, "Extensions apply to a specific message; " ~ pbmsg.name ~ " != " ~ ext.name);
	import std.conv;
	foreach(echild;ext.children) {
		bool extmatch = false;
		foreach(exten;pbmsg.exten_sets) {
			if (echild.index <= exten.max && echild.index >= exten.min) {
				extmatch = true;
				break;
			}
		}
		if (!extmatch) throw new Exception("The field number "~to!(string)(echild.index)~" for extension "~echild.name~" is not within a valid extension range for "~pbmsg.name);
	}

	// now check each child vs each extension already applied to see if there are conflicts
	foreach(dchild; pbmsg.child_exten) foreach(echild; ext.children) {
		if (dchild.index == echild.index) throw new Exception("Extensions "~dchild.name~" and "~echild.name~" to "~pbmsg.name~" have identical index number "~to!(string)(dchild.index));
	}
	pbmsg.child_exten ~= ext.children;

	return pbmsg;
}

unittest {
	auto foo =
ParserData("message Foo {
	optional int de = 5;
	extensions 1 to 4;
}
");
	auto extFoo =
ParserData("extend Foo {
	optional int blah = 1;
}
");

	auto Foo = PBMessage(foo);
	auto ExtFoo = PBExtension(extFoo);

	auto m = insertExtension(Foo, ExtFoo);
}
