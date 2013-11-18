dc?=dmd
Generator=source/dprotobuf/generator/common.d\
          source/dprotobuf/generator/d1lang.d\
          source/dprotobuf/generator/dlang.d\
			 source/dprotobuf/pbchild.d source/dprotobuf/pbenum.d\
			 source/dprotobuf/pbextension.d source/dprotobuf/pbgeneral.d\
          source/dprotobuf/pbmessage.d source/dprotobuf/pbroot.d


Library=source/dprotobuf/wireformat.d source/dprotobuf/d1support.d

all: libdprotobuf pbcompiler

libdprotobuf: $(Library) $(Generator)
	$(dc) $(args) -O -release -lib -oflibdprotobuf $^

pbc: pbcompiler/source/app.d $(Generator) $(Library)
	$(dc) $(args) -ofpbc $^
	
clean:
	rm *.o *.a
