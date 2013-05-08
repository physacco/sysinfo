NAME = sysinfo
VERSION = $(shell cat VERSION)
NAMEVER = $(NAME)-$(VERSION)
DISTPKG = $(NAMEVER).tar.gz
LIBDIR = $(shell erl -noinput -eval "io:format(code:lib_dir())." -s erlang halt)
INSTDIR = $(LIBDIR)/$(NAMEVER)

###
.PHONY: all compile run install clean dist

all: compile

compile:
	@./rebar compile

run: compile
	@erl -pa ebin -run sysmon

install: compile
	@mkdir -p $(INSTDIR)
	@cp -r * $(INSTDIR)

clean:
	@./rebar clean
	@rm -f $(DISTPKG)

dist:
	@git archive --format=tar --prefix=$(NAMEVER)/ HEAD | gzip > $(DISTPKG)
	@echo Package created: $(DISTPKG)
