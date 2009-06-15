// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbroot;
import ProtocolBuffer.pbgeneral;
import ProtocolBuffer.pbmessage;
import ProtocolBuffer.pbenum;
import std.string;
import std.stdio;

// XXX I intentionally left out all identifier validation routines, because the compiler knows how to resolve symbols. XXX
// XXX This means I don't have to write that code. XXX

struct PBRoot {
	PBMessage[]message_defs;
	PBEnum[]enum_defs;
	// this package name should translate directly to the module name of the implementation file
	// but I might want to mix everything in without a separate compiler...or make it available both ways
	char[]Package;
	// XXX need to support extensions here XXX
	// XXX need to support imports here (this will require an array of pbroots) XXX
	char[]toDString(char[]indent="") {
		char[]retstr = "";
		retstr ~= "module "~Package~";\n";
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

	// this should leave nothing in the string you pass in
	static PBRoot opCall(inout char[]pbstring)
	in {
		assert(pbstring.length);
	} body {
		// loop until the string is gone
		PBRoot root;
		// rip off whitespace before looking for the next definition
		pbstring = stripLWhite(pbstring);
		while(pbstring.length) {
			switch(typeNextElement(pbstring)){
			case PBTypes.PB_Package:
				root.Package = parsePackage(pbstring);
				break;
			case PBTypes.PB_Message:
				root.message_defs ~= PBMessage(pbstring);
				break;
			case PBTypes.PB_Enum:
				root.enum_defs ~= PBEnum(pbstring);
				break;
			case PBTypes.PB_Comment:
				stripValidChars(CClass.Comment,pbstring);
				break;
			default:
				throw new PBParseException("Root Definition("~root.Package~")","Either there's a definition here that isn't supported, or the definition isn't allowed here.");
				break;
			}
			// rip off whitespace before looking for the next definition
			pbstring = stripLWhite(pbstring);
		}
		return root;
	}

	static char[]parsePackage(inout char[]pbstring)
	in {
		assert(pbstring.length);
	} body {
		pbstring = pbstring["package".length..$];
		// strip any whitespace before the package name
		pbstring = stripLWhite(pbstring);
		// the next part of the string should be the package name up until the semicolon
		char[]Package = stripValidChars(CClass.MultiIdentifier,pbstring);
		// rip out any whitespace that might be here for some strange reason
		pbstring = stripLWhite(pbstring);
		// make sure the next character is a semicolon...
		if (pbstring[0] != ';') {
			throw new PBParseException("Package Definition","Whitespace is not allowed in package names.");
		}
		// actually rip off the ;
		pbstring = pbstring[1..$];
		// make sure this is valid
		if (!validateMultiIdentifier(Package)) throw new PBParseException("Package Identifier("~Package~")","Package identifier did not validate.");
		return Package;
	}

}

char[]pbstr = "   
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

unittest {
	writefln("unittest ProtocolBuffer.pbroot");
	auto root = PBRoot(pbstr);
	writefln(root.toDString);
	return 0;
}

version(unittests) {
int main() {return 0;}
}
