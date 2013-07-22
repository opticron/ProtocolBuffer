// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbroot;
import ProtocolBuffer.pbgeneral;
import ProtocolBuffer.pbmessage;
import ProtocolBuffer.pbenum;
import ProtocolBuffer.pbextension;
import ProtocolBuffer.conversion.dlang;
import ProtocolBuffer.conversion.d1lang;

version(D_Version2) {
	import std.algorithm;
	import std.range;
} else
	import ProtocolBuffer.d1support;

import std.string;
import std.stdio;

struct PBRoot {
	PBMessage[]message_defs;
	PBEnum[]enum_defs;
	string []imports;
	string Package;
	string[] comments;
	PBExtension[]extensions;
	string toDString() {
		return langD1();
	}
	string langD1() {
		string retstr = "";
		retstr ~= "import ProtocolBuffer.conversion.pbbinary;\n";
		retstr ~= "import std.string;\n\n";

		retstr ~= "version(D_Version2) {\n";
			retstr ~= "\timport std.conv;\n";
			retstr ~= "\tstring makeString(T)(T v) {\n";
			retstr ~= "\t\treturn to!(string)(v);\n";
			retstr ~= "\t}\n";
		retstr ~= "} else {\n";
			retstr ~= "\timport std.string;\n";
			retstr ~= "\tstring makeString(T)(T v) {\n";
			retstr ~= "\t\tstatic if(is(T == enum))\n";
			retstr ~= "\t\t\treturn toString(cast(int)v);\n";
			retstr ~= "\t\t\telse\n";
			retstr ~= "\t\t\treturn toString(v);\n";
			retstr ~= "\t}\n";
		retstr ~= "}\n";

		// do what we need for extensions defined here
		retstr ~= extensions.genExtString("");
		// write out enums
		foreach(pbenum;enum_defs) {
			retstr ~= toD1(pbenum, 0);
		}
		// write out message definitions
		foreach(pbmsg;message_defs) {
			retstr ~= toD1(pbmsg, 0);
		}
		return retstr;
    }
	string langD() {
		string retstr = "";
		retstr ~= "import ProtocolBuffer.conversion.pbbinary;\n";
		retstr ~= "import std.conv;\n";
		retstr ~= "import std.typecons;\n\n";

		retstr ~= "string makeString(T)(T v) {\n";
		retstr ~= "\treturn to!string(v);\n";
		retstr ~= "}\n";

		// do what we need for extensions defined here
		retstr ~= extensions.genExtString("");
		// write out enums
		foreach(pbenum;enum_defs) {
			retstr ~= toD(pbenum, 0);
		}
		// write out message definitions
		foreach(pbmsg;message_defs) {
			retstr ~= toD(pbmsg, 0);
		}
		return retstr;
	}

	static PBRoot opCall(string input)
	in {
		assert(!input.empty());
	} body {
		PBRoot root;
		auto pbstring = ParserData(input);
		// rip off whitespace before looking for the next definition
		pbstring = stripLWhite(pbstring);
		CommentManager storeComment;

		// loop until the string is gone
		while(!pbstring.input.empty()) {
			storeComment.lastElementType = typeNextElement(pbstring);
			storeComment.lastElementLine = pbstring.line;
			switch(storeComment.lastElementType){
			case PBTypes.PB_Package:
				root.Package = parsePackage(pbstring);
				break;
			case PBTypes.PB_Message:
				root.message_defs ~= PBMessage(pbstring);
				break;
			case PBTypes.PB_Extend:
				root.extensions ~= PBExtension(pbstring);
				break;
			case PBTypes.PB_Enum:
				root.enum_defs ~= PBEnum(pbstring);
				break;
			case PBTypes.PB_Comment:
				// Preserve at least one spacing in comments
				if(storeComment.line+1 < pbstring.line)
					if(!storeComment.comments.empty())
						storeComment ~= "";
				storeComment ~= stripValidChars(CClass.Comment,pbstring);
				storeComment.line = pbstring.line;
				break;
			case PBTypes.PB_Option:
				// rip of "option" and leading whitespace
				pbstring.input.skipOver("option");
				pbstring = stripLWhite(pbstring);
				ripOption(pbstring);
				break;
			case PBTypes.PB_Import:
				pbstring = pbstring["import".length..pbstring.length];
				pbstring = stripLWhite(pbstring);
				if (pbstring[0] != '"') throw new PBParseException("Root Definition("~root.Package~")","Imports must be quoted", pbstring.line);
				// save imports for use by the compiler code
				root.imports ~= ripQuotedValue(pbstring)[1..$-1];
				// ensure that the ; is removed
				pbstring = stripLWhite(pbstring);
				if (pbstring[0] != ';') throw new PBParseException("Root Definition("~root.Package~")","Missing ; after import \""~root.imports[$-1]~"\"", pbstring.line);
				pbstring = pbstring[1..pbstring.length];
				pbstring = stripLWhite(pbstring);
				break;
			default:
				throw new PBParseException("Root Definition("~root.Package~")","Either there's a definition here that isn't supported, or the definition isn't allowed here", pbstring.line);
			}
			pbstring.input.skipOver(";");
			// rip off whitespace before looking for the next definition
			// this needs to stay at the end
			pbstring = stripLWhite(pbstring);

			// Attach Comments to elements
			if(!storeComment.comments.empty()) {
				if(storeComment.line == storeComment.lastElementLine
				   || storeComment.line+3 > storeComment.lastElementLine) {
					switch(storeComment.lastElementType) {
						case PBTypes.PB_Comment:
							break;
						case PBTypes.PB_Message:
							root.message_defs[$-1].comments
								= storeComment.comments;
							goto default;
						case PBTypes.PB_Enum:
							root.enum_defs[$-1].comments
								= storeComment.comments;
							goto default;
						case PBTypes.PB_Package:
							root.comments
								= storeComment.comments;
							goto default;
						default:
							storeComment.comments = null;
					}
				}
			}
		}
		return root;
	}

	static string parsePackage(ref ParserData pbstring)
	in {
		assert(pbstring.length);
	} body {
		pbstring = pbstring["package".length..pbstring.length];
		// strip any whitespace before the package name
		pbstring = stripLWhite(pbstring);
		// the next part of the string should be the package name up until the semicolon
		string Package = stripValidChars(CClass.MultiIdentifier,pbstring);
		// rip out any whitespace that might be here for some strange reason
		pbstring = stripLWhite(pbstring);
		// make sure the next character is a semicolon...
		if (pbstring[0] != ';') {
			throw new PBParseException("Package Definition","Whitespace is not allowed in package names.", pbstring.line);
		}
		// actually rip off the ;
		pbstring = pbstring[1..pbstring.length];
		// make sure this is valid
		if (!validateMultiIdentifier(Package)) throw new PBParseException("Package Identifier("~Package~")","Package identifier did not validate.", pbstring.line);
		return Package;
	}

}


unittest {
	string pbstr = "
option optimize_for = SPEED;
package myfirstpackage;
// my comments hopefully won't explode anything
	message Person {required string name= 1;
	required int32 id =2;
	optional string email = 3 ;

	enum PhoneType{
	MOBILE= 0;HOME =1;
	// gotta make sure comments work everywhere
	WORK=2 ;}

	message PhoneNumber {
	required string number = 1;
	//woah, comments in a sub-definition
	optional PhoneType type = 2 ;
	}

	repeated PhoneNumber phone = 4;
}
//especially here
";

	writefln("unittest ProtocolBuffer.pbroot");
	auto root = PBRoot(pbstr);
	assert(root.Package == "myfirstpackage");
	assert(root.message_defs[0].name == "Person");
	assert(root.message_defs[0].comments.length == 1);
	assert(root.message_defs[0].message_defs[0].name == "PhoneNumber");
	assert(root.message_defs[0].enum_defs[0].name == "PhoneType");
}
