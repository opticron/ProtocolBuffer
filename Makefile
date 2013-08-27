dc?=dmd
Generator=conversion/common.d conversion/d1lang.d\
          conversion/dlang.d pbchild.d pbenum.d pbextension.d pbgeneral.d\
          pbmessage.d pbroot.d


Library=conversion/pbbinary.d d1support.d

all: libdprotobuf pbcompiler

libdprotobuf: $(Library)
	$(dc) $(args) -O -release -lib -oflibdprotobuf $^

pbcompiler: pbcompiler.d $(Generator) $(Library)
	$(dc) $(args) $^
	
clean:
	rm -rf *.o *.a pbcompiler
