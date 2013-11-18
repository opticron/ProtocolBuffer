/**
 * Provides common functions during language conversion.
 */
module dprotobuf.generator.common;

version(D_Version2) {
	import std.algorithm;
	import std.conv;
	import std.range;
	import std.regex;
} else {
	import std.string;
	import dprotobuf.d1support;
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

/**
 * Specifies how indentation should be applied to this line.
 *
 * open - specifies that this opens a block and should indent
 * future lines.
 *
 * close - specifies that this closes a block, itself and
 * future lines should indent one less.
 *
 * none - perform not modification to the indentation.
 */
enum Indent { none, open, close = 4 }

struct Memory {
	private CodeBuilder.Operation[][string] saved;
}

/**
 * An output range that provides extended functionality for
 * constructing a well formatted string of code.
 *
 * CodeBuilder has three main operations.
 *
 * $(UL
 *    $(LI put - Applies string directly to desired output)
 *    $(LI push - Stacks string for later)
 *    $(LI build - Constructs a sequence of strings)
 * )
 *
 * $(H1 put)
 *
 * The main operation for placing code into the buffer. This will sequentially
 * place code into the buffer. Similar operations are provided for the other
 * operations.
 *
 * $(D rawPut) will place the string without indentation added.
 *
 * One can place the current indentation level without code by calling put("");
 *
 * $(H1 push)
 *
 * This places code onto a stack. $(B pop) can be used to put the code into the
 * buffer.
 *
 * $(H1 build)
 *
 * Building code in a sequence can be pushed onto the stack, or saved to be put
 * into the buffer later.
 */
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

	/**
	 */
	static CodeBuilder opCall(int indentedCount) {
		CodeBuilder b;
		b.indentCount = indentedCount;
		return b;
	}

	/**
	 * Places str into the buffer.
	 *
	 * put("text", Indent.open); will indent "text" at the current level and
	 * future code will be indented one level.
	 *
	 * put("other", Indent.close); will indent "other" at one less the current
	 * indentation.
	 *
	 * put("}{", Indent.close | Indent.open) will indent "}{" at one less the
	 * current indentation and continue indentation for future code.
	 *
	 * rawPut provides the same operations but does not include the current
	 * indentation level.
	 *
	 * To place indentation but no other code use put("");
	 *
	 * To reduce indentation without inserting code use put(Indent.close);
	 */
	void put(string str, Indent indent = Indent.none) {
		switch(str) {
			case "":
				if(!indent)
					goto default;
				goto case;
			case "\n":
				goto case;
			case "\r\n":
				rawPut(str, indent);
				break;
			default:
				if(indent & Indent.close) indentCount--;
				rawPut(indented(indentCount));
				rawPut(str, indent & Indent.open);
		}
	}

	/// ditto
	void rawPut(string str, Indent indent = Indent.none) {
		upper ~= str;
		put(indent);
	}

	/// ditto
	void put(Indent indent) {
		assert(!(indent & Indent.close & Indent.open), "No-op indent");
		if(indent & Indent.close) indentCount--;
		if(indent & Indent.open) indentCount++;
	}

	/**
	 * Places str onto a stack that can latter be popped into
	 * the current buffer.
	 *
	 * See put for specifics.
	 */
	void push(string str, Indent indent = Indent.close) {
		lower ~= [Operation(str, indent)];
	}

	/// ditto
	void push(Indent indent) {
		lower ~= [Operation(null, indent)];
	}

	/// ditto
	void rawPush(string str, Indent indent = Indent.close) {
		lower ~= [Operation(str, indent, true)];
	}

	/// ditto
	void rawPush() {
		lower ~= [Operation(null, Indent.none, true)];
	}

	/**
	 * Places the top stack item into the buffer.
	 */
	void pop() {
		assert(!lower.empty(), "Can't pop empty buffer");

		foreach(op; lower.back())
			if(op.raw)
				rawPut(op.text, op.indent);
			else
				put(op.text, op.indent);

		lower.popBack();
		version(D_Version2) if(!__ctfe) assumeSafeAppend(lower);
	}

	/**
	 * Construct a code string outside of the current buffer.
	 *
	 * Used to construct a code string in sequence, as apposed
	 * to pushing the desired code in reverse (making it harder
	 * to read).
	 *
	 * A build can also be saved with a name and later called.
	 */
	void build(string str, Indent indent = Indent.none) {
		store ~= Operation(str, indent);
	}

	/// ditto
	void build(Indent indent) {
		store ~= Operation(null, indent);
	}

	/// ditto
	void buildRaw(string str, Indent indent = Indent.none) {
		store ~= Operation(str, indent, true);
	}

	/**
	 * See push and put, performed on the current build.
	 */
	void pushBuild() {
		lower ~= store;
		store = null;
	}

	/// ditto
	void pushBuild(string name) {
		lower ~= saved[name];
	}

	/// ditto
	void putBuild(string name) {
		pushBuild(name);
		pop();
	}


	/**
	 * Stores the build to be called on later with $(B name).
	 */
	void saveBuild(string name) {
		saved[name] = store;
		store = null;
	}

	Memory mem() {
		Memory m;
		m.saved = saved;
		return m;
	}

	/**
	 * Adds the memory to this CodeBuilder
	 */
	void mem(Memory m) {
		saved = m.saved;
	}

	/**
	 * Returns the buffer, applying an code remaining on the stack.
	 */
	string finalize() {
		while(!lower.empty())
			pop();
		return upper;
	}
}
