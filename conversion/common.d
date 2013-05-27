/**
 * Provides common functions during language conversion.
 */
module ProtocolBuffer.conversion.common;

version(D_Version2) {
	import std.algorithm;
	import std.conv;
	import std.range;
	import std.regex;
} else {
	import std.string;
	import ProtocolBuffer.d1support;
}

/*
 * Converts a numeric to an indent string
 */
string indented(int indentCount) {
    assert(indentCount > -1);
	version(D_Version2)
		return to!(string)(repeat("\t", indentCount).join.array);
	else
		return repeat("\t", indentCount);
}

enum Indent { none, open, close = 4 }

struct Memory {
	private CodeBuilder.Operation[][string] saved;
}

struct CodeBuilder {
	struct Operation {
		string text;
		Indent indent;
		bool raw;
	}
	private string upper;
	private Operation[][] lower;
	private Operation[] store;
	private Operation[][string] saved;

	int indentCount;

	static CodeBuilder opCall(int indentedCount) {
		CodeBuilder b;
		b.indentCount = indentedCount;
		return b;
	}

	void rawPut(string str, Indent indent = Indent.none) {
		upper ~= str;
		put(indent);
	}

	void put(string str, Indent indent = Indent.none) {
		switch(str) {
			case "":
				if(!indent)
					goto default;
			case "\n":
			case "\r\n":
				rawPut(str, indent);
				break;
			default:
				if(indent & Indent.close) indentCount--;
				rawPut(indented(indentCount));
				rawPut(str, indent & Indent.open);
		}
	}

	void put(Indent indent) {
		assert(!(indent & Indent.close & Indent.open), "No-op indent");
		if(indent & Indent.close) indentCount--;
		if(indent & Indent.open) indentCount++;
	}

	void push(string str, Indent indent = Indent.close) {
		lower ~= [Operation(str, indent)];
	}

	void push(Indent indent) {
		lower ~= [Operation(null, indent)];
	}

	void rawPush(string str, Indent indent = Indent.close) {
		lower ~= [Operation(str, indent, true)];
	}

	void rawPush() {
		lower ~= [Operation(null, Indent.none, true)];
	}

	void pop() {
		assert(!lower.empty(), "Can't pop empty buffer");

		foreach(op; lower.back())
			if(op.raw)
				rawPut(op.text, op.indent);
			else
				put(op.text, op.indent);

		lower.popBack();
		version(D_Version2) if(__ctfe) { } else
			assumeSafeAppend(lower);
	}

	void build(string str, Indent indent = Indent.none) {
		store ~= Operation(str, indent);
	}

	void build(Indent indent) {
		store ~= Operation(null, indent);
	}

	void buildRaw(string str, Indent indent = Indent.none) {
		store ~= Operation(str, indent, true);
	}

	void pushBuild() {
		lower ~= store;
		store = null;
	}

	void pushBuild(string name) {
		lower ~= saved[name];
	}

	void putBuild(string name) {
		pushBuild(name);
		pop();
	}


	void saveBuild(string name) {
		saved[name] = store;
		store = null;
	}

	Memory mem() {
		Memory m;
		m.saved = saved;
		return m;
	}

	void mem(Memory m) {
		saved = m.saved;
	}

	string finalize() {
		while(!lower.empty())
			pop();
		return upper;
	}
}
