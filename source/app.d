module pbcompiler;
// compiler for .proto protocol buffer definition files that generates D code
//
import dprotobuf.pbroot;
import dprotobuf.pbextension;
import dprotobuf.pbmessage;
import dprotobuf.pbgeneral;
import dprotobuf.generator.d1lang;
import dprotobuf.generator.dlang;

import std.conv;
import std.file;
import std.path;
import std.stdio;
import std.string;

version(D_Version2) {
	import std.getopt;
	import std.algorithm;
	import std.range;
} else
	import dprotobuf.d1support;

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
	*dst = insertExtension(*dst, ext);

	// it looks like we have a match!
	writefln("Applying extensions to %s",dst.name);
	return 1;
}

// this function digs through a given root to see if it has the message described by the dotstring
PBMessage*findMessage(string impstr,string message) {
	PBRoot root = docroots[impstr];
	return searchMessages(root, ParserData(message));
}

// this is where all files are written, no real processing is done here
void writeRoots(Language lang) {
	foreach(root;docroots) {
		string tmp;
		tmp ~= addComments(root.comments).finalize();
		tmp ~= "module "~root.Package~";\n";
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
