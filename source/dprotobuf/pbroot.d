// this file implements the structures and lexer for the protocol buffer format
// required to parse a protocol buffer file or tree and generate
// code to read and write the specified format
module dprotobuf.pbroot;
import dprotobuf.pbgeneral;
import dprotobuf.pbmessage;
import dprotobuf.pbenum;
import dprotobuf.pbextension;

version(D_Version2) {
	import std.algorithm;
	import std.range;
} else
	import dprotobuf.d1support;

import std.string;
import std.stdio;

struct PBRoot {
	PBMessage[]message_defs;
	PBEnum[]enum_defs;
	string []imports;
	string Package;
	string[] comments;
	PBExtension[]extensions;

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
			auto curElementType = typeNextElement(pbstring);
			auto curElementLine = pbstring.line;
			switch(curElementType){
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
				storeComment.line = curElementLine;
				if(curElementLine == storeComment.lastElementLine)
					tryAttachComments(root, storeComment);
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
			storeComment.lastElementType = curElementType;
			storeComment.lastElementLine = curElementLine;
			tryAttachComments(root, storeComment);

		}
		return root;
	}

	static void tryAttachComments(ref PBRoot root, ref CommentManager storeComment) {
		// Attach Comments to elements
		if(!storeComment.comments.empty()) {
			if(storeComment.line == storeComment.lastElementLine
			   || storeComment.line+3 > storeComment.lastElementLine) {
				switch(storeComment.lastElementType) {
					case PBTypes.PB_Comment:
					case PBTypes.PB_MultiComment:
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

// Verify comments attach to root/module/package
unittest {
	string pbstr = "// Openning comments
		package openning;";
	auto root = PBRoot(pbstr);
	assert(root.Package == "openning");
	assert(root.comments.length == 1);
	assert(root.comments[0] == "// Openning comments");
}

// Verify multiline comments attach to root/module/package
unittest {
	string pbstr = "/* Openning\ncomments */
		package openning;";
	auto root = PBRoot(pbstr);
	assert(root.Package == "openning");
	assert(root.comments.length == 2);
	assert(root.comments[0] == "/* Openning");
	assert(root.comments[1] == "comments */");
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

PBExtension[] getExtensions(T)(T root) {
	PBExtension[]ret;
	ret ~= root.extensions;
	foreach(msg;root.message_defs) {
		ret ~= getExtensions(msg);
	}
	return ret;
} unittest {
	enum instr =
ParserData("extend Foo {
	optional int blah = 1;
}
message Bar {
	optional int de = 5;
	extend FooBar {
		optional string da = 2;
	}
}
");

assert(getExtensions(PBRoot(instr)).map!(x => x.name).equal(["Foo", "FooBar"]));
}

// this function digs through a given root to see if it has the message
// described by the dotstring
PBMessage* searchForMessage(ref PBRoot root, string message) {
	return searchMessages(root, ParserData(message));
}

/// Ditto
PBMessage* searchMessages(T)(ref T root, ParserData message)
in {
	assert(message.length);
} body {
	string name = stripValidChars(CClass.Identifier,message);
	if (message.length) {
		// rip off the leading .
		message = message[1..message.length];
	}
	// this is terminal, so run through the children to find a match
	foreach(ref msg;root.message_defs) {
		if (msg.name == name) {
			if (!message.length) {
				return &msg;
			} else {
				return searchMessages(msg,message);
			}
		}
	}
	return null;
} unittest {
	enum instr =
ParserData("
message Foo {
}
message Bar {
	optional int de = 5;
}
");

	auto root = PBRoot(instr);
    assert(searchForMessage(root, "Foo").name == "Foo");
}

auto applyExtensions(PBRoot root, PBExtension[] exts) {
	foreach(ext; exts) {
		auto m = searchForMessage(root, ext.name);
		if(m) {
			*m = insertExtension(*m, ext);
			break;
		}
	}
	return root;
} static unittest {
	enum foo =
ParserData("message Foo {
	optional int de = 5;
	extensions 1 to 4;
}
extend Foo {
	optional int blah = 1;
}
");

	enum Foo = PBRoot(foo);
	enum ExtFoo = Foo.getExtensions();

	applyExtensions(Foo, ExtFoo);
}
