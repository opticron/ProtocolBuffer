// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbmessage;
import ProtocolBuffer.pbgeneral;
import ProtocolBuffer.pbenum;
import ProtocolBuffer.pbchild;
import ProtocolBuffer.pbextension;
import std.string;
import std.stdio;

// I intentionally left out all identifier validation routines, because the compiler knows how to resolve symbols. 
// This means I don't have to write that code. 

struct PBMessage {
	char[]name;
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
	char[]toDString(char[]indent) {
		char[]retstr = "";
		retstr ~= indent~(indent.length?"static ":"")~"class "~name~" {\n";
		indent = indent~"	";
		retstr ~= indent~"// deal with unknown fields\n";
		retstr ~= indent~"byte[]ufields;\n";
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
		retstr ~= indent~"static "~name~" opCall(inout byte[]input) {\n";
		retstr ~= indent~"	return Deserialize(input);\n";
		retstr ~= indent~"}\n";
		
		// guaranteed to work, since we tack on a tab earlier
		indent = indent[0..$-1];
		retstr ~= indent~"}\n";
		return retstr;
	}

	char[]genSerCode(char[]indent) {
		char[]ret = "";
		// use -1 as a default value, since a nibble can not produce that number
		ret ~= indent~"byte[]Serialize(int field = -1) {\n";
		indent = indent~"	";
		// codegen is fun!
		ret ~= indent~"byte[]ret;\n";
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
		ret ~= indent~"	retobj.ufields ~= _toVarint(header)~ripUField(input,getWireType(header));\n";
		ret ~= indent~"	break;\n";
		ret ~= indent~"}\n";
		indent = indent[0..$-1];
		ret ~= indent~"}\n";

		// check for required fields
		foreach(pbchild;child_exten) if (pbchild.modifier == "required") {
			ret ~= indent~"if (retobj._has__exten_"~pbchild.name~" == false) throw new Exception(\"Did not find a "~pbchild.name~" in the message parse.\");\n";
		}
		foreach(pbchild;children) if (pbchild.modifier == "required") {
			ret ~= indent~"if (retobj._has_"~pbchild.name~" == false) throw new Exception(\"Did not find a "~pbchild.name~" in the message parse.\");\n";
		}
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

	char[]genMergeCode(char[]indent) {
		char[]ret;
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

	void ripExtenRange(inout char[]pbstring) {
		pbstring = pbstring["extensions".length..$];
		pbstring = stripLWhite(pbstring);
		allow_exten ext;
		// expect next to be numeric
		char[]tmp = stripValidChars(CClass.Numeric,pbstring);
		if (!tmp.length) throw new PBParseException("Message Parse("~name~" extension range)","Unable to rip min and max for extension range");
		ext.min = cast(int)atoi(tmp);
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
			ext.max = cast(int)atoi(tmp);
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

char[]genExtString(PBExtension[]extens,char[]indent) {
	// we just need to generate a list of static const variables
	char[]ret;
	foreach(exten;extens) foreach(child;exten.children) {
		ret ~= indent~"const int "~child.name~" = "~toString(child.index)~";\n";
	}
	return ret;
}

unittest {
	char[]instring = "message glorm{\noptional int32 i32test = 1;\nmessage simple { }\noptional simple quack = 5;\n}\n";
	char[]compstr = 
"class glorm {
	// deal with unknown fields
	byte[]ufields;
	static class simple {
		// deal with unknown fields
		byte[]ufields;
		byte[]Serialize(int field = -1) {
			byte[]ret;
			ret ~= ufields;
			// take care of header and length generation if necessary
			if (field != -1) {
				ret = genHeader(field,2)~toVarint(ret.length,field)[1..$]~ret;
			}
			return ret;
		}
		// if we're root, we can assume we own the whole string
		// if not, the first thing we need to do is pull the length that belongs to us
		static simple Deserialize(inout byte[]manip,bool isroot=true) {
			auto retobj = new simple;
			byte[]input = manip;
			// cut apart the input string
			if (!isroot) {
				uint len = fromVarint!(uint)(manip);
				input = manip[0..len];
				manip = manip[len..$];
			}
			while(input.length) {
				int header = fromVarint!(int)(input);
				switch(getFieldNumber(header)) {
				default:
					// rip off unknown fields
					retobj.ufields ~= _toVarint(header)~ripUField(input,getWireType(header));
					break;
				}
			}
			return retobj;
		}
		void MergeFrom(simple merger) {
		}
		static simple opCall(inout byte[]input) {
			return Deserialize(input);
		}
	}
	int _i32test;
	int i32test() {
		return _i32test;
	}
	void i32test(int input_var) {
		_i32test = input_var;
		_has_i32test = true;
	}
	bool _has_i32test = false;
	bool has_i32test () {
		return _has_i32test;
	}
	void clear_i32test () {
		_has_i32test = false;
	}
	simple _quack;
	simple quack() {
		return _quack;
	}
	void quack(simple input_var) {
		_quack = input_var;
		_has_quack = true;
	}
	bool _has_quack = false;
	bool has_quack () {
		return _has_quack;
	}
	void clear_quack () {
		_has_quack = false;
	}
	byte[]Serialize(int field = -1) {
		byte[]ret;
		ret ~= toVarint(i32test,1);
		static if (is(simple:Object)) {
			ret ~= quack.Serialize(5);
		} else {
			// this is an enum, almost certainly
			ret ~= toVarint!(int)(quack,5);
		}
		ret ~= ufields;
		// take care of header and length generation if necessary
		if (field != -1) {
			ret = genHeader(field,2)~toVarint(ret.length,field)[1..$]~ret;
		}
		return ret;
	}
	// if we're root, we can assume we own the whole string
	// if not, the first thing we need to do is pull the length that belongs to us
	static glorm Deserialize(inout byte[]manip,bool isroot=true) {
		auto retobj = new glorm;
		byte[]input = manip;
		// cut apart the input string
		if (!isroot) {
			uint len = fromVarint!(uint)(manip);
			input = manip[0..len];
			manip = manip[len..$];
		}
		while(input.length) {
			int header = fromVarint!(int)(input);
			switch(getFieldNumber(header)) {
			case 1:
				if (getWireType(header) == 0) {
					retobj._i32test = fromVarint!(int)(input);
				} else {
					throw new Exception(\"Invalid wiretype \"~std.string.toString(getWireType(header))~\" for variable type int32\");
				}
				retobj._has_i32test = true;
				break;
			case 5:
				static if (is(simple:Object)) {
					retobj._quack = simple.Deserialize(input,false);
				} else {
					// this is an enum, almost certainly
					if (getWireType(header) == 0) {
						retobj._quack = fromVarint!(int)(input);
					} else {
						throw new Exception(\"Invalid wiretype \"~std.string.toString(getWireType(header))~\" for variable type simple\");
					}
				}
				retobj._has_quack = true;
				break;
			default:
				// rip off unknown fields
				retobj.ufields ~= _toVarint(header)~ripUField(input,getWireType(header));
				break;
			}
		}
		return retobj;
	}
	void MergeFrom(glorm merger) {
		if (merger.has_i32test) i32test = merger.i32test;
		if (merger.has_quack) quack = merger.quack;
	}
	static glorm opCall(inout byte[]input) {
		return Deserialize(input);
	}
}
";
	writefln("unittest ProtocolBuffer.pbmessage");
	auto msg = PBMessage(instring);
	debug {
		writefln("Correct output:\n%s",compstr);
		writefln("Generated output:\n%s",msg.toDString(""));
	}
	assert(msg.toDString("") == compstr);
	debug writefln("");
}

