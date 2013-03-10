// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbmessage;

import ProtocolBuffer.pbgeneral;
import ProtocolBuffer.pbenum;
import ProtocolBuffer.pbchild;
import ProtocolBuffer.pbextension;

import std.algorithm;
import std.conv;
import std.range;
import std.stdio;
import std.string;

// I intentionally left out all identifier validation routines, because the compiler knows how to resolve symbols. 
// This means I don't have to write that code. 

struct PBMessage {
	string name;
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
	// XXX need to support options correctly 
	// XXX need to support services at some point 
	string toDString(string indent) {
		string retstr = "";
		retstr ~= indent~(indent.length?"static ":"")~"class "~name~" {\n";
		indent = indent~"	";
		retstr ~= indent~"// deal with unknown fields\n";
		retstr ~= indent~"ubyte[]ufields;\n";
		// fill the class with goodies!
		// first, we'll do the enums!
		foreach(pbenum;enum_defs) {
			retstr ~= pbenum.toDString(indent);
		}
		// now, we'll do the nested messages
		foreach(pbmsg;message_defs) {
			retstr ~= pbmsg.toDString(indent);
		}
		// do the individual instantiations
		foreach(pbchild;children) {
			retstr ~= pbchild.toDString(indent);
		}
		// last, do the extension instantiations
		foreach(pbchild;child_exten) {
			retstr ~= pbchild.genExtenCode(indent);
		}
		// here is where we add the code to serialize and deserialize
		retstr ~= genSerCode(indent);
		retstr ~= genDesCode(indent);
		// define merging function
		retstr ~= genMergeCode(indent);
		// deal with what little we need to do for extensions
		retstr ~= extensions.genExtString(indent~"static ");
		// include a static opcall to do deserialization to make coding simpler
		retstr ~= indent~"static "~name~" opCall(ref ubyte[]input) {\n";
		retstr ~= indent~"	return Deserialize(input);\n";
		retstr ~= indent~"}\n";

		// guaranteed to work, since we tack on a tab earlier
		indent = indent[0..$-1];
		retstr ~= indent~"}\n";
		return retstr;
	}

	string genSerCode(string indent) {
		string ret = "";
		// use -1 as a default value, since a nibble can not produce that number
		ret ~= indent~"ubyte[]Serialize(int field = -1) {\n";
		indent = indent~"	";
		// codegen is fun!
		ret ~= indent~"ubyte[]ret;\n";
		// serialization code goes here
		foreach(pbchild;children) {
			ret ~= pbchild.genSerLine(indent);
		}
		foreach(pbchild;child_exten) {
			ret ~= pbchild.genSerLine(indent,true);
		}
		// tack on unknown bytes
		ret ~= indent~"ret ~= ufields;\n";

		// include code to determine if we need to add a tag and a length
		ret ~= indent~"// take care of header and length generation if necessary\n";
		ret ~= indent~"if (field != -1) {\n";
		// take care of length calculation and integration of header and length
		ret ~= indent~"	ret = genHeader(field,2)~toVarint(ret.length,field)[1..$]~ret;\n";
		ret ~= indent~"}\n";

		ret ~= indent~"return ret;\n";
		indent = indent[0..$-1];
		ret ~= indent~"}\n";
		return ret;
	}

	string genDesCode(string indent) {
		string ret = "";
		// add comments
		ret ~= indent~"// if we're root, we can assume we own the whole string\n";
		ret ~= indent~"// if not, the first thing we need to do is pull the length that belongs to us\n";
		ret ~= indent~"static "~name~" Deserialize(ref ubyte[]manip,bool isroot=true) {return new "~name~"(manip,isroot);}\n";
		ret ~= indent~"this(){}\n";
		ret ~= indent~"this(ref ubyte[]manip,bool isroot=true) {\n";
		indent = indent~"	";
		ret ~= indent~"ubyte[]input = manip;\n";

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
		ret ~= indent~"int header = fromVarint!(int)(input);\n";
		ret ~= indent~"switch(getFieldNumber(header)) {\n";
		//here goes the meat, handily, it is generated in the children
		foreach(pbchild;children) {
			ret ~= pbchild.genDesLine(indent);
		}
		foreach(pbchild;child_exten) {
			ret ~= pbchild.genDesLine(indent,true);
		}
		// take care of default case
		ret ~= indent~"default:\n";
		ret ~= indent~"	// rip off unknown fields\n";
		ret ~= indent~"	ufields ~= _toVarint(header)~ripUField(input,getWireType(header));\n";
		ret ~= indent~"	break;\n";
		ret ~= indent~"}\n";
		indent = indent[0..$-1];
		ret ~= indent~"}\n";

		// check for required fields
		foreach(pbchild;child_exten) if (pbchild.modifier == "required") {
			ret ~= indent~"if (_has__exten_"~pbchild.name~" == false) throw new Exception(\"Did not find a "~pbchild.name~" in the message parse.\");\n";
		}
		foreach(pbchild;children) if (pbchild.modifier == "required") {
			ret ~= indent~"if (_has_"~pbchild.name~" == false) throw new Exception(\"Did not find a "~pbchild.name~" in the message parse.\");\n";
		}
		indent = indent[0..$-1];
		ret ~= indent~"}\n";
		return ret;
	}

	// string-modifying constructor
	static PBMessage opCall(ref string pbstring)
	in {
		assert(pbstring.length);
	} body {
		// things we currently support in a message: messages, enums, and children(repeated, required, optional)
		// first things first, rip off "message"
		pbstring.skipOver("message");
		// now rip off the next set of whitespace
		pbstring = stripLWhite(pbstring);
		// get message name
		string name = stripValidChars(CClass.Identifier,pbstring);
		PBMessage message;
		message.name = name;
		// rip off whitespace
		pbstring = stripLWhite(pbstring);
		// make sure the next character is the opening {
		if (pbstring[0] != '{') {
			throw new PBParseException("Message Definition","Expected next character to be '{'. You may have a space in your message name: "~name);
		}
		// rip off opening {
		pbstring.popFront();
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
				stripValidChars(CClass.Comment,pbstring);
				break;
			case PBTypes.PB_Option:
				// rip of "option" and leading whitespace
				pbstring = stripLWhite(pbstring["option".length..$]);
				ripOption(pbstring);
				break;
			default:
				throw new PBParseException("Message Definition","Only extend, service, package, and message are allowed here.");
			}
			// this needs to stay at the end
			pbstring = stripLWhite(pbstring);
		}
		// rip off the }
		pbstring = pbstring[1..$];
		return message;
	}

	string genMergeCode(string indent) {
		string ret;
		ret ~= indent~"void MergeFrom("~name~" merger) {\n";
		indent = indent~"	";
		// merge code
		foreach(pbchild;children) if (pbchild.modifier != "repeated") {
			ret ~= indent~"if (merger.has_"~pbchild.name~") "~pbchild.name~" = merger."~pbchild.name~";\n";
		} else {
			ret ~= indent~"if (merger.has_"~pbchild.name~") add_"~pbchild.name~"(merger."~pbchild.name~");\n";
		}
		indent = indent[0..$-1];
		ret ~= indent~"}\n";
		return ret;
	}

	void ripExtenRange(ref string pbstring) {
		pbstring = pbstring["extensions".length..$];
		pbstring = stripLWhite(pbstring);
		allow_exten ext;
		// expect next to be numeric
		string tmp = stripValidChars(CClass.Numeric,pbstring);
		if (!tmp.length) throw new PBParseException("Message Parse("~name~" extension range)","Unable to rip min and max for extension range");
		ext.min = to!int(tmp);
		pbstring = stripLWhite(pbstring);
		// make sure we have "to"
		if (pbstring[0..2].icmp("to") != 0) {
			throw new PBParseException("Message Parse("~name~" extension range)","Unable to rip min and max for extension range");
		}
		// rip of "to"
		pbstring = pbstring[2..$];
		pbstring = stripLWhite(pbstring);
		// check for "max" and rip it if necessary
		if (pbstring[0..3].icmp("max") == 0) {
			pbstring = pbstring[3..$];
			// (1<<29)-1 is defined as the maximum extension value
			ext.max = (1<<29)-1;
		} else {
			tmp = stripValidChars(CClass.Numeric,pbstring);
			if (!tmp.length) throw new PBParseException("Message Parse("~name~" extension range)","Unable to rip min and max for extension range");
			ext.max = to!int(tmp);
			if (ext.max > (1<<29)-1) {
				throw new PBParseException("Message Parse("~name~" extension range)","Max defined extension value is greater than allowable max");
			}
		}
		pbstring = stripLWhite(pbstring);
		// check for ; and rip it off
		if (pbstring[0] != ';') {
			throw new PBParseException("Message Parse("~name~" extension range)","Missing ; at end of extension range definition");
		}
		pbstring = pbstring[1..$];
		exten_sets ~= ext;
	}
}

string genExtString(PBExtension[]extens,string indent) {
	// we just need to generate a list of static const variables
	string ret;
	foreach(exten;extens) foreach(child;exten.children) {
		ret ~= indent~"const int "~child.name~" = "~to!string(child.index)~";\n";
	}
	return ret;
}

unittest {
	enum instring = "message glorm{\noptional int32 i32test = 1;\nmessage simple { }\noptional simple quack = 5;\n}\n";

    PBMessage PBCompileTime(string pbstring) {
        return PBMessage(pbstring);
    }

	writefln("unittest ProtocolBuffer.pbmessage");
	enum msg = PBCompileTime(instring);
    assert(msg.name == "glorm");
    assert(msg.message_defs[0].name == "simple");
    assert(msg.children.length == 2);
	debug writefln("");
}

