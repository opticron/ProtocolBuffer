// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pblexer;
import std.string;
import std.stdio;

enum PBTypes {
	PB_Package=1,
	PB_Enum,
	PB_Message,
	PB_Option,
	PB_Extension,
	PB_Extend,
	PB_Service,
	PB_Import,
	PB_Optional,
	PB_Required,
	PB_Repeated,
	PB_Comment,
}

// character classes for parsing
enum CClass {
	Package,
	Identifier,
	Numeric,
	Comment,
}

struct PBChild {
	char[]modifier;
	char[]type;
	char[]name;
	int index;
	static PBChild opCall(PBTypes type,inout char[]pbstring) {
		PBChild child;
		// all of the modifiers happen to be the same length...whodathunkit
		// also, it's guaranteed to be there by previous code, so it shouldn't need error checking
		child.modifier = pbstring[0.."repeated".length];
		pbstring = pbstring["repeated".length..$];
		pbstring = stripLWhite(pbstring);
		// now we want to pull out the type
		child.type = stripValidChars(CClass.Identifier,pbstring);
		if (!child.type.length) throw new PBParseException("Child Instantiation","Could not pull type from definition.");
		if (!validIdentifier(child.type)) throw new PBParseException("Child Instantiation","Invalid type identifier "~child.type~".");
		pbstring = stripLWhite(pbstring);
		// pull out the name of the instance, now
		child.name = stripValidChars(CClass.Identifier,pbstring);
		if (!child.name.length) throw new PBParseException("Child Instantiation("~child.type~")","Could not pull name from definition.");
		if (!validIdentifier(child.name)) throw new PBParseException("Child Instantiation("~child.type~")","Invalid name identifier "~child.name~".");
		pbstring = stripLWhite(pbstring);
		// make sure the next character is =, because we need to snag the index, next
		if (pbstring[0] != '=') throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Missing '=' for child instantiation.");
		pbstring = pbstring[1..$];
		pbstring = stripLWhite(pbstring);
		// pull numeric index
		char[]tmp = stripValidChars(CClass.Numeric,pbstring);
		if (!tmp.length) throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Could not pull numeric index.");
		child.index = atoi(tmp);
		if (child.index == 0) throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Numeric index can not be 0.");
		pbstring = stripLWhite(pbstring);
		// now, check to see if we have a semicolon so we can be done
		if (pbstring[0] == ';') {
			// rip off the semicolon
			pbstring = pbstring[1..$];
			return child;
		}
		// we're still here, so there may be options in []
		if (pbstring[0] != '[') throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","No idea what to do with string after index.");
		// XXX support options! XXX
		throw new PBParseException("Child Instantiation("~child.type~" "~child.name~")","Options are not currently supported.");
		return child;
	}

}

struct PBEnum {
	char[]name;
	char[][int]values;
	// XXX need to support options at some point XXX
	static PBEnum opCall(inout char[]pbstring) {
		PBEnum pbenum;
		// strip of "enum" and following whitespace
		pbstring = pbstring["enum".length..$];
		pbstring = stripLWhite(pbstring);
		// grab name
		pbenum.name = stripValidChars(CClass.Identifier,pbstring);
		if (!pbenum.name.length) throw new PBParseException("Enum Definition","Could not pull name from definition.");
		if (!validIdentifier(pbenum.name)) throw new PBParseException("Enum Definition","Invalid name identifier "~pbenum.name~".");
		pbstring = stripLWhite(pbstring);
		// make sure the next character is the opening {
		if (pbstring[0] != '{') {
			throw new PBParseException("Enum Definition("~pbenum.name~")","Expected next character to be '{'. You may have a space in your enum name: "~pbenum.name);
		}
		// rip off opening {
		pbstring = pbstring[1..$];
		// now we're ready to enter the loop and parse children
		while(pbstring[0] != '}') {
			pbstring = stripLWhite(pbstring);
			if (pbstring.length>1 && pbstring[0..2] == "//") {
				// rip out the comment...
				stripValidChars(CClass.Comment,pbstring);
			} else {
				// start parsing, we shouldn't have any whitespace here
				pbenum.grabEnumValue(pbstring);
			}
		}
		// rip off the }
		pbstring = pbstring[1..$];
		return pbenum;
	}

	void grabEnumValue(inout char[]pbstring) {
		// whitespace has already been ripped
		// snag item name
		char[]tmp = stripValidChars(CClass.Identifier,pbstring);
		if (!tmp.length) throw new PBParseException("Enum Definition("~name~")","Could not pull item name from definition.");
		if (!validIdentifier(tmp)) throw new PBParseException("Enum Definition("~name~")","Invalid item name identifier "~tmp~".");
		pbstring = stripLWhite(pbstring);
		// make sure to traverse the '='
		if (pbstring[0] != '=') throw new PBParseException("Enum Definition("~name~"."~tmp~")","Expected '=', but got something else. You may have a space in one of your enum items.");
		pbstring = pbstring[1..$];
		pbstring = stripLWhite(pbstring);
		// now parse a numeric
		char[]num = stripValidChars(CClass.Numeric,pbstring);
		if (!num.length) throw new PBParseException("Enum Definition("~name~"."~tmp~")","Could not pull numeric enum value.");
		values[atoi(tmp)] = tmp;
		pbstring = stripLWhite(pbstring);
		// make sure we snatch a semicolon
		if (pbstring[0] != ';') throw new PBParseException("Enum Definition("~name~"."~tmp~"="~num~")","Expected ';'.");
		pbstring = pbstring[1..$];
	}
}

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
	static PBMessage opCall(inout char[]pbstring) {
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
				message.children ~= PBChild(type,pbstring);
				break;
			case PBTypes.PB_Comment:
				stripValidChars(CClass.Comment,pbstring);
				break;
			default:
				// XXX fix this message XXX
				throw new PBParseException("Message Definition","Only extend, service, package, and message are allowed here.");
				break;
			}
			// this needs to stay at the end
			pbstring = stripLWhite(pbstring);
		}
		// rip off the }
		pbstring = pbstring[1..$];
		return message;
	}
}

struct PBRoot {
	PBMessage[]messages;
	// this package name should translate directly to the module name of the implementation file
	// but I might want to mix everything in without a separate compiler...or make it available both ways
	char[]Package;
	// XXX need to support extensions here XXX
	// XXX need to support imports here XXX
	static PBRoot opCall(inout char[]pbstring) {
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
				root.messages ~= PBMessage(pbstring);
				break;
			case PBTypes.PB_Comment:
				stripValidChars(CClass.Comment,pbstring);
				break;
			default:
				throw new PBParseException("Protocol Buffer Definition Root","Only extend, service, package, and message are allowed here.");
				break;
			}
			// rip off whitespace before looking for the next definition
			pbstring = stripLWhite(pbstring);
		}
		return root;
	}

	static char[]parsePackage(inout char[]pbstring) {
		pbstring = pbstring["package".length..$];
		// strip any whitespace before the package name
		pbstring = stripLWhite(pbstring);
		// the next part of the string should be the package name up until the semicolon
		char[]Package = stripValidChars(CClass.Package,pbstring);
		// rip out any whitespace that might be here for some strange reason
		pbstring = stripLWhite(pbstring);
		// make sure the next character is a semicolon...
		if (pbstring[0] != ';') {
			throw new PBParseException("Package Definition","Whitespace is not allowed in package names.");
		}
		// make sure this is valid
		validatePackage(Package);
		return Package;
	}

	static void validatePackage(char[]ident) {
		// XXX assuming that the identifier can't start or end with . and individual parts can't start with numerics XXX
		char[][]parts = split(ident,".");
		foreach(part;parts) {
			if (!part.length) throw new PBParseException("Package Name Validation","Package identifiers may not contain zero-length sections.");
			if (!validIdentifier(part)) throw new PBParseException("Package Name Validation","Package sections may not start with numerics.");
		}
	}
}


class PBParseException:Exception {
	char[]locus;
	char[]error;
	this(char[]location,char[]problem) {
		locus = location;
		error = problem;
		super(locus~": "~error);
	}
}


PBTypes typeNextElement(in char[]pbstring) {
	// we want to check for // type comments here, since there doesn't necessarily have to be a space after the opener
	if (pbstring.length>1 && pbstring[0..2] == "//") return PBTypes.PB_Comment;
	int i=0;
	for(;i<pbstring.length && !iswhite(pbstring[i]);i++){}
	auto type = pbstring[0..i];
	switch(type) {
	case "package":
		return PBTypes.PB_Package;
		break;
	case "enum":
		return PBTypes.PB_Enum;
		break;
	case "message":
		return PBTypes.PB_Message;
		break;
	case "repeated":
		return PBTypes.PB_Repeated;
		break;
	case "required":
		return PBTypes.PB_Required;
		break;
	case "optional":
		return PBTypes.PB_Optional;
		break;
	case "option":
	case "extension":
	case "extend":
	case "service":
	case "import":
		throw new PBParseException("Protocol Buffer Definition",capitalize(type)~" definitions are not currently supported.");
		break;
	default:
		throw new PBParseException("Protocol Buffer Definition","Unknown element type "~type~".");
		break;
	}
}

// this will rip off the next token
char[]stripValidChars(CClass cc,inout char[]pbstring) {
	int i=0;
	for(;i<pbstring.length && isValidChar(cc,pbstring[i]);i++){}
	char[]tmp = pbstring[0..i];
	pbstring = pbstring[i..$];
	return tmp;
}

// allowed characters vary by type
bool isValidChar(CClass cc,char pc) {
	switch(cc) {
	case CClass.Package:
	case CClass.Identifier:
		if (pc >= 'a' && pc <= 'z') return true;
		if (pc >= 'A' && pc <= 'Z') return true;
		if (pc == '.' && cc == CClass.Package) return true;
	case CClass.Numeric:
		if (pc >= '0' && pc <= '9') return true;
		return false;
		break;
	case CClass.Comment:
		if (pc == '\n') return false;
		if (pc == '\r') return false;
		if (pc == '\f') return false;
		return true;
		break;
	default:
		throw new PBParseException("Name Validation","Cannot validate characters for this PBType name.");
	}
}

bool validIdentifier(char[]ident) {
	// XXX for now, we assume that the identifier was pulled using the stripvalidchars function, so we only have to check the first character XXX
	if (ident[0] >= '0' && ident[0] <= '9') return false;
	return true;
}

char[] stripLWhite(char[] s)
{
    size_t i;

    for (i = 0; i < s.length; i++)
    {
        if (!iswhite(s[i]))
            break;
    }
    return s[i .. s.length];
}

unittest {
	writefln("unittest ProtocolBuffer.pbroot");
	char[]pbstring = "   
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
	auto root = PBRoot(pbstring);
	return 0;
}

version(unittests) {
int main() {return 0;}
}
