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
		retstr ~= genSerCode(indent);
		retstr ~= genDesCode(indent);
		// generate accessors
		foreach(pbchild;children) {
			retstr ~= pbchild.genAccessor(indent);
		}
		
		// guaranteed to work, since we tack on a tab earlier
		indent = indent[0..$-1];
		retstr ~= indent~"}\n";
		return retstr;
	}

	char[]genSerCode(char[]indent) {
		char[]ret = "";
		// use 16 as a default value, since a nibble can not produce that number
		ret ~= indent~"byte[]Serialize(byte field = 16) {\n";
		indent = indent~"	";
		// codegen is fun!
		ret ~= indent~"byte[]ret;\n";
		// serialization code goes here
		foreach(pbchild;children) {
			ret ~= pbchild.genSerLine(indent);
		}

		// include code to determine if we need to add a tag and a length
		ret ~= indent~"// take care of header and length generation if necessary\n";
		ret ~= indent~"if (field != 16) {\n";
		// take care of length calculation and integration of header and length
		ret ~= indent~"	ret ~= genHeader(field,2)~toVarint(ret.length,field)[1..$]~ret;\n";
		ret ~= indent~"}\n";

		ret ~= indent~"return ret;\n";
		indent = indent[0..$-1];
		ret ~= indent~"}\n";
		return ret;
	}

	char[]genDesCode(char[]indent) {
		char[]ret = "";
		// add comments
		ret ~= indent~"// if we're root, we can assume we own the whole string\n";
		ret ~= indent~"// if not, the first thing we need to do is pull the length that belongs to us\n";
		ret ~= indent~"static "~name~" Deserialize(inout byte[]manip,bool isroot=true) {\n";
		indent = indent~"	";
		ret ~= indent~"auto retobj = new "~name~";\n";
		ret ~= indent~"byte[]input = manip;\n";

		ret ~= indent~"// cut apart the input string\n";
		ret ~= indent~"if (!isroot) {\n";
		indent = indent~"	";
		ret ~= indent~"uint len = fromVarint!(uint)(manip);\n";
		ret ~= indent~"input = manip[0..len];\n";
		ret ~= indent~"manip = manip[len..$];\n";
		indent = indent[0..$-1];
		ret ~= indent~"}\n";

		// deserialization code goes here
		ret ~= indent~"while(input.length) {\n";
		indent = indent~"	";
		ret ~= indent~"byte header = input[0];\n";
		ret ~= indent~"input = input[1..$];\n";
		ret ~= indent~"switch(getFieldNumber(header)) {\n";
		//here goes the meat, handily, it is generated in the children
		foreach(pbchild;children) {
			ret ~= pbchild.genDesLine(indent);
		}
		// take care of default case
		ret ~= indent~"default:\n";
		ret ~= indent~"// XXX I don't know what to do with unknown fields, yet\n";
		// XXX finish this
		ret ~= indent~"}\n";
		indent = indent[0..$-1];
		ret ~= indent~"}\n";

		ret ~= indent~"return retobj;\n";
		indent = indent[0..$-1];
		ret ~= indent~"}\n";
		return ret;
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

