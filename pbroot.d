// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbroot;
import ProtocolBuffer.pbgeneral;
import ProtocolBuffer.pbmessage;
import ProtocolBuffer.pbenum;
import ProtocolBuffer.pbextension;

import std.algorithm;
import std.range;
import std.string;
import std.stdio;

struct PBRoot {
	PBMessage[]message_defs;
	PBEnum[]enum_defs;
	string []imports;
	string Package;
	PBExtension[]extensions;
	string toDString(string indent="") {
		string retstr = "";
		retstr ~= "import ProtocolBuffer.pbhelper;\n";
		// do what we need for extensions defined here
		retstr ~= extensions.genExtString(indent);
		// write out enums
		foreach(pbenum;enum_defs) {
			retstr ~= pbenum.toDString(indent);
		}
		// write out message definitions
		foreach(pbmsg;message_defs) {
			retstr ~= pbmsg.toDString(indent);
		}
		return retstr;
	}

	static PBRoot opCall(string input)
	in {
		assert(!input.empty);
	} body {
		PBRoot root;
        auto pbstring = ParserData(input);
		// rip off whitespace before looking for the next definition
		pbstring = stripLWhite(pbstring);
		// loop until the string is gone
		while(pbstring.length) {
			switch(typeNextElement(pbstring)){
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
				stripValidChars(CClass.Comment,pbstring);
				break;
			case PBTypes.PB_Option:
				// rip of "option" and leading whitespace
                pbstring.input.skipOver("option");
				pbstring = stripLWhite(pbstring);
				ripOption(pbstring);
				break;
			case PBTypes.PB_Import:
				pbstring = pbstring["import".length..$];
				pbstring = stripLWhite(pbstring);
				if (pbstring[0] != '"') throw new PBParseException("Root Definition("~root.Package~")","Imports must be quoted", pbstring.line);
				// save imports for use by the compiler code
				root.imports ~= ripQuotedValue(pbstring)[1..$-1];
				// ensure that the ; is removed
				pbstring = stripLWhite(pbstring);
				if (pbstring[0] != ';') throw new PBParseException("Root Definition("~root.Package~")","Missing ; after import \""~root.imports[$-1]~"\"", pbstring.line);
				pbstring = pbstring[1..$];
				pbstring = stripLWhite(pbstring);
				break;
			default:
				throw new PBParseException("Root Definition("~root.Package~")","Either there's a definition here that isn't supported, or the definition isn't allowed here", pbstring.line);
			}
			pbstring.input.skipOver(";");
			// rip off whitespace before looking for the next definition
			// this needs to stay at the end
			pbstring = stripLWhite(pbstring);
		}
		return root;
	}

	static string parsePackage(ref ParserData pbstring)
	in {
		assert(pbstring.length);
	} body {
		pbstring = pbstring["package".length..$];
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
		pbstring = pbstring[1..$];
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
    assert(root.message_defs[0].message_defs[0].name == "PhoneNumber");
    assert(root.message_defs[0].enum_defs[0].name == "PhoneType");
}

version(unittests) {
int main() {return 0;}
}
