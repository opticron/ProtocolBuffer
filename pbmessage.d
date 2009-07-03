// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbmessage;
import ProtocolBuffer.pbgeneral;
import ProtocolBuffer.pbenum;
import ProtocolBuffer.pbchild;
import std.string;
import std.stdio;

// XXX I intentionally left out all identifier validation routines, because the compiler knows how to resolve symbols. XXX
// XXX This means I don't have to write that code. XXX

struct PBMessage {
	char[]name;
	// message definitions that actually occur within this message
	PBMessage[]message_defs;
	// enum definitions that actually occur within this message
	PBEnum[]enum_defs;
	// variable/structure/enum instances
	PBChild[]children;
	// XXX i need to deal with extensions at some point XXX
	// XXX need to support options at some point XXX
	// XXX need to support services at some point XXX
	char[]toDString(char[]indent) {
		char[]retstr = "";
		// XXX do we want to inherit from a class or use a templated class? XXX
		retstr ~= indent~"class "~name~" {\n";
		indent = indent~"	";
		// fill the class with goodies!
		// first, we'll do the enums!
		foreach(pbenum;enum_defs) {
			retstr ~= pbenum.toDString(indent);
		}
		// now, we'll do the nested messages
		foreach(pbmsg;message_defs) {
			retstr ~= pbmsg.toDString(indent);
		}
		// last, do the individual instantiations
		foreach(pbchild;children) {
			retstr ~= pbchild.toDString(indent);
		}
		// here is where we add the code to serialize and deserialize
		
		// guaranteed to work, since we tack on a tab earlier
		indent = indent[0..$-1];
		retstr ~= indent~"}\n";
		return retstr;
	}

	// string-modifying constructor
	static PBMessage opCall(inout char[]pbstring)
	in {
		assert(pbstring.length);
	} body {
		// things we currently support in a message: messages, enums, and children(repeated, required, optional)
		// first things first, rip off "message"
		pbstring = pbstring["message".length..$];
		// now rip off the next set of whitespace
		pbstring = stripLWhite(pbstring);
		// get message name
		char[]name = stripValidChars(CClass.Identifier,pbstring);
		PBMessage message;
		message.name = name;
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
			PBTypes type = typeNextElement(pbstring);
			switch(type){
			case PBTypes.PB_Message:
				message.message_defs ~= PBMessage(pbstring);
				break;
			case PBTypes.PB_Enum:
				message.enum_defs ~= PBEnum(pbstring);
				break;
			case PBTypes.PB_Repeated:
			case PBTypes.PB_Required:
			case PBTypes.PB_Optional:
				message.children ~= PBChild(pbstring);
				break;
			case PBTypes.PB_Comment:
				stripValidChars(CClass.Comment,pbstring);
				break;
			default:
				// XXX fix this message XXX
				throw new PBParseException("Message Definition","Only extend, service, package, and message are allowed here.");
			}
			// this needs to stay at the end
			pbstring = stripLWhite(pbstring);
		}
		// rip off the }
		pbstring = pbstring[1..$];
		return message;
	}
}

unittest {
	char[]instring = "message glorm{\noptional int32 i32test = 1;\nmessage simple { }\noptional simple quack = 5;\n}\n";
	char[]compstr = "class glorm {\n	class simple {\n	}\n	int i32test;\n	simple quack;\n}\n";
	writefln("unittest ProtocolBuffer.pbmessage");
	auto msg = PBMessage(instring);
	debug {
		writefln("Correct output:\n%s",compstr);
		writefln("Generated output:\n%s",msg.toDString(""));
	}
	assert(msg.toDString("") == compstr);
	debug writefln("");
}

