Protocol Buffer
===============

This is an implementation of Google's Protocol Buffers for the D programming language. [Protocol Buffer](https://developers.google.com/protocol-buffers/docs/overview) is a binary wire transfer format.

Source code generated using this library has the proto file comments transferred as documentation comments. Important accessors which do not have comments are given an empty documentation comment so generated docs will mention their existence.

Status
------

This is an incomplete implementation of the spec. It is expanded on an as needed basis, pull requests and bug reports welcome.

This library supports output for version 1 and version 2 of dlang, the version 1 output is compatible with both compilers, while version 2 output provides an interface more natural to the language.

* Supports basic types (message, enum, extension)
* Supports options: packed, deprecated and default.

Todo
----

* Expose unknown options to runtime
* Finalize on interface for D2
* Support services
* Support C style multi-line comments

D Interface
-----------

The source output for D is meant to feel more natural than the official compiler provides to other languages.

A message is translated into a struct and provides a static opCall to deserialize a ubyte[]. A Serialize function is provided to turn the message into a ubyte[]. And all message fields are fields of the struct wrapped in Nullable!().

D v1 Interface
--------------

The interface provided for version 1 of the language (also usable in version 2) provides a slightly different structure.

A message is translated into a class and provides a constructor to deserialize a ubyte[]. A Serialize function is provided to turn the message into a ubyte[]. And all message fields are accessors.

For repeated types use add\_fieldName() to add elements.
