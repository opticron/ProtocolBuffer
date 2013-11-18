module dprotobuf.d1support;

import std.string;

version(D_Version2) {
} else {
    int to(T)(string v) {
        return atoi(v);
    }

    string to(T)(int v) {
        return toString(v);
    }

    string to(T, S)(ulong v, S redix) {
        return toString(v, redix);
    }

    bool empty(T)(T[] v) {
        return !v.length;
    }

    T back(T)(T[] arr) {
        return arr[$-1];
    }

    void popBack(T)(ref T[] arr) {
        arr = arr[0..$-1];
    }

    bool skipOver(ref string str, string c) {
        if(str.length < c.length) return false;

        if(str[0..c.length] == c) {
            str = str[c.length..$];
            return true;
        }
        return false;
    }
}
