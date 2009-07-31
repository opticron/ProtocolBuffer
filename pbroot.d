// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module ProtocolBuffer.pbroot;
import ProtocolBuffer.pbgeneral;
import ProtocolBuffer.pbmessage;
import ProtocolBuffer.pbenum;
import ProtocolBuffer.pbextension;
import std.string;
import std.stdio;

struct PBRoot {
	PBMessage[]message_defs;
	PBEnum[]enum_defs;
	char[][]imports;
	char[]Package;
	PBExtension[]extensions;
	char[]toDString(char[]indent="") {
		char[]retstr = "";
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
				pbstring = stripLWhite(pbstring["option".length..$]);
				ripOption(pbstring);
				break;
			case PBTypes.PB_Import:
				pbstring = pbstring["import".length..$];
				pbstring = stripLWhite(pbstring);
				if (pbstring[0] != '"') throw new PBParseException("Root Definition("~root.Package~")","Imports must be quoted");
				// save imports for use by the compiler code
				root.imports ~= ripQuotedValue(pbstring)[1..$-1];
				// ensure that the ; is removed
				pbstring = stripLWhite(pbstring);
				if (pbstring[0] != ';') throw new PBParseException("Root Definition("~root.Package~")","Missing ; after import \""~root.imports[$-1]~"\"");
				pbstring = pbstring[1..$];
				pbstring = stripLWhite(pbstring);
				break;
			default:
				throw new PBParseException("Root Definition("~root.Package~")","Either there's a definition here that isn't supported, or the definition isn't allowed here");
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


unittest {
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
	char[]compstr = 
"import ProtocolBuffer.pbhelper;
class Person {
	// deal with unknown fields
	byte[]ufields;
	enum PhoneType {
		MOBILE = 0,
		HOME = 1,
		WORK = 2,
	}
	static class PhoneNumber {
		// deal with unknown fields
		byte[]ufields;
		char[] _number;
		char[] number() {
			return _number;
		}
		void number(char[] input_var) {
			_number = input_var;
			_has_number = true;
		}
		bool _has_number = false;
		bool has_number () {
			return _has_number;
		}
		void clear_number () {
			_has_number = false;
		}
		PhoneType _type;
		PhoneType type() {
			return _type;
		}
		void type(PhoneType input_var) {
			_type = input_var;
			_has_type = true;
		}
		bool _has_type = false;
		bool has_type () {
			return _has_type;
		}
		void clear_type () {
			_has_type = false;
		}
		byte[]Serialize(byte field = 16) {
			byte[]ret;
			ret ~= toByteString(number,cast(byte)1);
			static if (is(PhoneType:Object)) {
				ret ~= type.Serialize(cast(byte)2);
			} else {
				// this is an enum, almost certainly
				ret ~= toVarint!(int)(type,cast(byte)2);
			}
			ret ~= ufields;
			// take care of header and length generation if necessary
			if (field != 16) {
				ret = genHeader(field,2)~toVarint(ret.length,field)[1..$]~ret;
			}
			return ret;
		}
		// if we're root, we can assume we own the whole string
		// if not, the first thing we need to do is pull the length that belongs to us
		static PhoneNumber Deserialize(inout byte[]manip,bool isroot=true) {
			auto retobj = new PhoneNumber;
			byte[]input = manip;
			// cut apart the input string
			if (!isroot) {
				uint len = fromVarint!(uint)(manip);
				input = manip[0..len];
				manip = manip[len..$];
			}
			while(input.length) {
				byte header = input[0];
				input = input[1..$];
				switch(getFieldNumber(header)) {
				case 1:
					retobj._number = fromByteString!(char[])(input);
					retobj._has_number = true;
					break;
					case 2:
					static if (is(PhoneType:Object)) {
						retobj._type = PhoneType.Deserialize(input,false);
					} else {
						// this is an enum, almost certainly
						retobj._type = fromVarint!(int)(input);
					}
					retobj._has_type = true;
					break;
				default:
					// rip off unknown fields
					retobj.ufields ~= header~ripUField(input,getWireType(header));
					break;
				}
			}
			if (retobj._has_number == false) throw new Exception(\"Did not find a number in the message parse.\");
			return retobj;
		}
		void MergeFrom(PhoneNumber merger) {
			if (merger.has_number) number = merger.number;
			if (merger.has_type) type = merger.type;
		}
		static PhoneNumber opCall(inout byte[]input) {
			return Deserialize(input);
		}
	}
	char[] _name;
	char[] name() {
		return _name;
	}
	void name(char[] input_var) {
		_name = input_var;
		_has_name = true;
	}
	bool _has_name = false;
	bool has_name () {
		return _has_name;
	}
	void clear_name () {
		_has_name = false;
	}
	int _id;
	int id() {
		return _id;
	}
	void id(int input_var) {
		_id = input_var;
		_has_id = true;
	}
	bool _has_id = false;
	bool has_id () {
		return _has_id;
	}
	void clear_id () {
		_has_id = false;
	}
	char[] _email;
	char[] email() {
		return _email;
	}
	void email(char[] input_var) {
		_email = input_var;
		_has_email = true;
	}
	bool _has_email = false;
	bool has_email () {
		return _has_email;
	}
	void clear_email () {
		_has_email = false;
	}
	PhoneNumber[]_phone;
	PhoneNumber[]phone() {
		return _phone;
	}
	void phone(PhoneNumber[]input_var) {
		_phone = input_var;
	}
	bool has_phone () {
		return _phone.length?1:0;
	}
	void clear_phone () {
		_phone = null;
	}
	int phone_size () {
		return _phone.length;
	}
	void add_phone (PhoneNumber __addme) {
		_phone ~= __addme;
	}
	void add_phone (PhoneNumber[]__addme) {
		_phone ~= __addme;
	}
	byte[]Serialize(byte field = 16) {
		byte[]ret;
		ret ~= toByteString(name,cast(byte)1);
		ret ~= toVarint(id,cast(byte)2);
		ret ~= toByteString(email,cast(byte)3);
		foreach(iter;phone) {
			static if (is(PhoneNumber:Object)) {
				ret ~= iter.Serialize(cast(byte)4);
			} else {
				// this is an enum, almost certainly
				ret ~= toVarint!(int)(iter,cast(byte)4);
			}
		}
		ret ~= ufields;
		// take care of header and length generation if necessary
		if (field != 16) {
			ret = genHeader(field,2)~toVarint(ret.length,field)[1..$]~ret;
		}
		return ret;
	}
	// if we're root, we can assume we own the whole string
	// if not, the first thing we need to do is pull the length that belongs to us
	static Person Deserialize(inout byte[]manip,bool isroot=true) {
		auto retobj = new Person;
		byte[]input = manip;
		// cut apart the input string
		if (!isroot) {
			uint len = fromVarint!(uint)(manip);
			input = manip[0..len];
			manip = manip[len..$];
		}
		while(input.length) {
			byte header = input[0];
			input = input[1..$];
			switch(getFieldNumber(header)) {
			case 1:
				retobj._name = fromByteString!(char[])(input);
				retobj._has_name = true;
				break;
			case 2:
				retobj._id = fromVarint!(int)(input);
				retobj._has_id = true;
				break;
			case 3:
				retobj._email = fromByteString!(char[])(input);
				retobj._has_email = true;
				break;
				case 4:
				static if (is(PhoneNumber:Object)) {
					retobj._phone = PhoneNumber.Deserialize(input,false);
				} else {
					// this is an enum, almost certainly
				if (getWireType(header) != 2) {
						retobj._phone ~= fromVarint!(int)(input);
					} else {
						retobj._phone ~= fromPacked!(PhoneNumber,)(input);
					}
				}
				break;
			default:
				// rip off unknown fields
				retobj.ufields ~= header~ripUField(input,getWireType(header));
				break;
			}
		}
		if (retobj._has_name == false) throw new Exception(\"Did not find a name in the message parse.\");
		if (retobj._has_id == false) throw new Exception(\"Did not find a id in the message parse.\");
		return retobj;
	}
	void MergeFrom(Person merger) {
		if (merger.has_name) name = merger.name;
		if (merger.has_id) id = merger.id;
		if (merger.has_email) email = merger.email;
		if (merger.has_phone) add_phone(merger.phone);
	}
	static Person opCall(inout byte[]input) {
		return Deserialize(input);
	}
}
";
	writefln("unittest ProtocolBuffer.pbroot");
	auto root = PBRoot(pbstr);
	debug {
		writefln("Correct string:\n%s",compstr);
		writefln("Generated string:\n%s",root.toDString);
	}
	assert(root.toDString == compstr);
	debug writefln("");
}

version(unittests) {
int main() {return 0;}
}
