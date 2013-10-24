// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbmessage;

import ProtocolBuffer.pbgeneral;
import ProtocolBuffer.pbenum;
import ProtocolBuffer.pbchild;
import ProtocolBuffer.pbextension;

version(D_Version2) {
	import std.algorithm;
	import std.range;
} else
	import ProtocolBuffer.d1support;

import std.conv;
import std.stdio;
import std.string;

// I intentionally left out all identifier validation routines, because the compiler knows how to resolve symbols. 
// This means I don't have to write that code. 

struct PBMessage {
	string name;
	string[] comments;
	// message definitions that actually occur within this message
	PBMessage[]message_defs;
	// enum definitions that actually occur within this message
	PBEnum[]enum_defs;
	// variable/structure/enum instances
	PBChild[]children;
	// this is for the compiler to stuff things into when it finds applicable extensions to the class
	PBChild[]child_exten;
	// this is for actual read extensions
	PBExtension[]extensions;
	// these set the allowable bounds for extensions to this message
	struct allow_exten {
		int min=-1;
		int max=-1;
	}
	allow_exten[]exten_sets;

	// string-modifying constructor
	static PBMessage opCall(ref ParserData pbstring)
	in {
		assert(pbstring.length);
	} body {
		// things we currently support in a message: messages, enums, and children(repeated, required, optional)
		// first things first, rip off "message"
		pbstring.input.skipOver("message");
		// now rip off the next set of whitespace
		pbstring = stripLWhite(pbstring);
		// get message name
		string name = stripValidChars(CClass.Identifier,pbstring);
		PBMessage message;
		message.name = name;
		// rip off whitespace
		pbstring = stripLWhite(pbstring);
		// make sure the next character is the opening {
		if(!pbstring.input.skipOver("{")) {
			throw new PBParseException("Message Definition","Expected next character to be '{'. You may have a space in your message name: "~name, pbstring.line);
		}

		// prep for loop spinup by removing extraneous whitespace
		pbstring = stripLWhite(pbstring);
		CommentManager storeComment;

		// now we're ready to enter the loop and parse children
		while(pbstring[0] != '}') {
			// start parsing, we shouldn't have any whitespace here
			auto curElementType = typeNextElement(pbstring);
			auto curElementLine = pbstring.line;
			switch(curElementType){
			case PBTypes.PB_Message:
				message.message_defs ~= PBMessage(pbstring);
				break;
			case PBTypes.PB_Enum:
				message.enum_defs ~= PBEnum(pbstring);
				break;
			case PBTypes.PB_Extend:
				message.extensions ~= PBExtension(pbstring);
				break;
			case PBTypes.PB_Extension:
				message.ripExtenRange(pbstring);
				break;
			case PBTypes.PB_Repeated:
			case PBTypes.PB_Required:
			case PBTypes.PB_Optional:
				message.children ~= PBChild(pbstring);
				break;
			case PBTypes.PB_Comment:
				// Preserve at least one spacing in comments
				if(storeComment.line+1 < pbstring.line)
					if(!storeComment.comments.empty())
						storeComment ~= "";
				storeComment ~= stripValidChars(CClass.Comment,pbstring);
				storeComment.line = curElementLine;
				if(curElementLine == storeComment.lastElementLine)
					tryAttachComments(message, storeComment);
				break;
			case PBTypes.PB_MultiComment:
				foreach(c; ripComment(pbstring))
					storeComment ~= c;
				storeComment.line = pbstring.line;
				break;
			case PBTypes.PB_Option:
				// rip of "option" and leading whitespace
				pbstring.input.skipOver("option");
				pbstring = stripLWhite(pbstring);
				ripOption(pbstring);
				break;
			default:
				throw new PBParseException("Message Definition","Only extend, service, package, and message are allowed here.", pbstring.line);
			}
			pbstring.input.skipOver(";");
			// this needs to stay at the end
			pbstring = stripLWhite(pbstring);
			storeComment.lastElementType = curElementType;
			storeComment.lastElementLine = curElementLine;
			tryAttachComments(message, storeComment);
		}
		// rip off the }
		pbstring.input.skipOver("}");
		return message;
	}

	static void tryAttachComments(ref PBMessage message, ref CommentManager storeComment) {
		// Attach Comments to elements
		if(!storeComment.comments.empty()) {
			if(storeComment.line == storeComment.lastElementLine
			   || storeComment.line+3 > storeComment.lastElementLine) {
				switch(storeComment.lastElementType) {
					case PBTypes.PB_Comment:
					case PBTypes.PB_MultiComment:
						break;
					case PBTypes.PB_Message:
						message.message_defs[$-1].comments
							= storeComment.comments;
						goto default;
					case PBTypes.PB_Enum:
						message.enum_defs[$-1].comments
							= storeComment.comments;
						goto default;
					case PBTypes.PB_Repeated:
					case PBTypes.PB_Required:
					case PBTypes.PB_Optional:
						message.children[$-1].comments
							= storeComment.comments;
						goto default;
					default:
						storeComment.comments = null;
				}
			}
		}
	}
	void ripExtenRange(ref ParserData pbstring) {
		pbstring = pbstring["extensions".length..pbstring.length];
		pbstring = stripLWhite(pbstring);
		allow_exten ext;
		// expect next to be numeric
		string tmp = stripValidChars(CClass.Numeric,pbstring);
		if (!tmp.length) throw new PBParseException("Message Parse("~name~" extension range)","Unable to rip min and max for extension range", pbstring.line);
		ext.min = to!(int)(tmp);
		pbstring = stripLWhite(pbstring);
		// make sure we have "to"
		if (pbstring.input[0..2].icmp("to") != 0) {
			throw new PBParseException("Message Parse("~name~" extension range)","Unable to rip min and max for extension range", pbstring.line);
		}
		// rip of "to"
		pbstring = pbstring[2..pbstring.length];
		pbstring = stripLWhite(pbstring);
		// check for "max" and rip it if necessary
		if (pbstring.input[0..3].icmp("max") == 0) {
			pbstring = pbstring[3..pbstring.length];
			// (1<<29)-1 is defined as the maximum extension value
			ext.max = (1<<29)-1;
		} else {
			tmp = stripValidChars(CClass.Numeric,pbstring);
			if (!tmp.length) throw new PBParseException("Message Parse("~name~" extension range)","Unable to rip min and max for extension range", pbstring.line);
			ext.max = to!(int)(tmp);
			if (ext.max > (1<<29)-1) {
				throw new PBParseException("Message Parse("~name~" extension range)","Max defined extension value is greater than allowable max", pbstring.line);
			}
		}
		pbstring = stripLWhite(pbstring);
		// check for ; and rip it off
		if (pbstring[0] != ';') {
			throw new PBParseException("Message Parse("~name~" extension range)","Missing ; at end of extension range definition", pbstring.line);
		}
		pbstring = pbstring[1..pbstring.length];
		exten_sets ~= ext;
	}
}

string genExtString(PBExtension[]extens,string indent) {
	// we just need to generate a list of static const variables
	string ret;
	foreach(exten;extens) foreach(child;exten.children) {
		ret ~= indent~"const int "~child.name~" = "~to!(string)(child.index)~";\n";
	}
	return ret;
}

unittest {
	auto instring = ParserData("message glorm{\noptional int32 i32test = 1;\nmessage simple { }\noptional simple quack = 5;\n}\n");

	writefln("unittest ProtocolBuffer.pbmessage");
	auto msg = PBMessage(instring);
	assert(msg.name == "glorm");
	assert(msg.message_defs[0].name == "simple");
	assert(msg.children.length == 2);

	auto str = ParserData("message Person {
		// I comment types
		message PhoneNumber {
		/* Multi\n    line\n*/
		required string number = 1;
		optional PhoneType type = 2 ;// Their type of phone
	}}");

	auto ms = PBMessage(str);
	assert(ms.name == "Person");
	assert(ms.message_defs[0].name == "PhoneNumber");
	assert(ms.message_defs[0].comments[0] == "// I comment types");
	assert(ms.message_defs[0].children[0].comments[0] == "/* Multi");
	assert(ms.message_defs[0].children[0].comments[1] == "    line");
	assert(ms.message_defs[0].children[0].comments[2] == "*/");
	assert(ms.message_defs[0].children[1].comments[0] == "// Their type of phone");
}
