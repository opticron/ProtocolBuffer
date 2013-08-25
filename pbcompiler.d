module pbcompiler;
// compiler for .proto protocol buffer definition files that generates D code
//
import ProtocolBuffer.pbroot;
import ProtocolBuffer.pbextension;
import ProtocolBuffer.pbmessage;
import ProtocolBuffer.pbgeneral;
import ProtocolBuffer.conversion.d1lang;
import ProtocolBuffer.conversion.dlang;

import std.conv;
import std.file;
import std.path;
import std.stdio;
import std.string;

version(D_Version2) {
	import std.getopt;
	import std.algorithm;
} else
	import ProtocolBuffer.d1support;

// our tree of roots to play with, so that we can apply multiple extensions to a given document
PBRoot[string] docroots;

enum Language {
	D1,
	D2,
}

int main(string[] args) {
	version(D_Version2) {
		Language lang = Language.D2;
		getopt(args, config.passThrough,
		       "lang", &lang
		      );
	} else
		Language lang = Language.D1;

	// rip off the first arg, because that's the name of the program
	args = args[1..$];

	if (!args.length) throw new Exception("No proto files supplied on the command line!");

	foreach (arg;args) {
		readRoot(arg);
	}
	applyExtensions();
	writeRoots(lang);
	return 0;
}

// returns package name
string readRoot(string filename) {
	string contents = cast(string)read(filename);
	auto root = PBRoot(contents);
	string fname = root.Package;
	if (!fname.length) {
		if (filename.length>6 && filename[$-6..$].icmp(".proto") == 0) {
			fname = filename[0..$-6];
		} else {
			fname = filename;
		}
	}
	root.Package = fname;
	foreach(ref imp;root.imports) {
		imp = readRoot(imp);
	}
	// store this for later use under its package name
	docroots[root.Package] = root;
	return root.Package;
}

// we run through the whole list looking for extensions and applying them
void applyExtensions() {
	foreach(root;docroots) {
		// make sure something can only extend what it has access to (including where it was defined)
		writefln("Probing root %s for extensions",root.Package);
		PBExtension[]extlist = getExtensions(root);
		foreach(ext;extlist) {
			// check the current node first (just in case)
			if (root.Package.applyExtension(ext)) continue;
			foreach(imp;root.imports) {
				// break out of the import loop to jump to the next extension
				if (imp.applyExtension(ext)) break;
			}
		}
	}
}

// attempt to apply an individual extension to a node identifier
// returns 1 if applied
int applyExtension(string imp,PBExtension ext) {
	writefln("Attempting to apply extension %s",ext.name);
	string tmp = ext.name;
	bool impflag = false;
	tmp.skipOver(imp);
	// now look for a message that matches the section within the current import
	PBMessage*dst = imp.findMessage(tmp);
	if (dst is null) {
		writefln("Found no destination to apply extension to %s in import \"%s\"",ext.name,imp);
		if (impflag) throw new Exception("Found an import path match \""~imp~"\", but unable to apply extension \""~ext.name~"\'");
		return 0;
	}
	// we have something we might want to apply it to! this is exciting!
	// make sure it's within the allowed extensions
	foreach(echild;ext.children) {
		bool extmatch = false;
		foreach(exten;dst.exten_sets) {
			if (echild.index <= exten.max && echild.index >= exten.min) {
				extmatch = true;
				break;
			}
		}
		if (!extmatch) throw new Exception("The field number "~to!(string)(echild.index)~" for extension "~echild.name~" is not within a valid extension range for "~dst.name);
	}
	// now check each child vs each extension already applied to see if there are conflicts
	foreach(dchild;dst.child_exten) foreach(echild;ext.children) {
		if (dchild.index == echild.index) throw new Exception("Extensions "~dchild.name~" and "~echild.name~" to "~dst.name~" have identical index number "~to!(string)(dchild.index));
	}
	// it looks like we have a match!
	writefln("Applying extensions to %s",dst.name);
	dst.child_exten ~= ext.children;
	return 1;
}

// this function digs through a given root to see if it has the message described by the dotstring
PBMessage*findMessage(string impstr,string message) {
	PBRoot root = docroots[impstr];
	return searchMessages(root, ParserData(message));
}

PBMessage*searchMessages(T)(ref T root, ParserData message)
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
}

PBExtension[]getExtensions(T)(T root) {
	PBExtension[]ret;
	ret ~= root.extensions;
	foreach(msg;root.message_defs) {
		ret ~= getExtensions(msg);
	}
	return ret;
}

// this is where all files are written, no real processing is done here
void writeRoots(Language lang) {
	foreach(root;docroots) {
		string tmp;
		tmp = "module "~root.Package~";\n";
		// write out imports
		foreach(imp;root.imports) {
			tmp ~= "import "~imp~";\n";
		}
		switch(lang) {
			case Language.D1:
				tmp ~= langD1(root);
				break;
			case Language.D2:
				tmp ~= langD(root);
				break;
			default:
				assert(false);
		}
		string fname = root.Package.tr(".","/")~".d";
		version(D_Version2) string dname = fname.dirName();
		else string dname = fname.getDirName();
		// check to see if we need to create the directory
		if (dname.length && !dname.exists()) {
			dname.mkdirRecurse();
		}
		std.file.write(fname,tmp);
	}
}

void mkdirRecurse(in string  pathname)
{
	version(D_Version2) string left = dirName(pathname);
	else string left = getDirName(pathname);
	exists(left) || mkdirRecurse(left);
	mkdir(pathname);
}
