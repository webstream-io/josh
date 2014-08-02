CC=gcc
CFLAGS=-O2

OBJ=nss_josh.o

%.o: %.c
	$(CC) -Wall -fPIC -c -o $@ $< $(CFLAGS)

libnss_josh.so.2: $(OBJ)
	$(CC) -shared -o $@ $^ -Wl,-soname,libnss_josh.so.2 $(CFLAGS)

clean:
	rm -f *.o *~ libnss_josh.so.2

install:
	ln -sf $(CURDIR)/libnss_josh.so.2 /lib

uninstall:
	rm /lib/libnss_josh.so.2
