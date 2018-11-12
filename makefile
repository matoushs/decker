executable := $(shell stack path | grep local-install-root | sed "s/local-install-root: //")/bin/decker
base-name := decker
version := $(shell grep "version: " package.yaml | sed "s/version: *//")
branch := $(shell git branch | grep \* | cut -d ' ' -f2)
local-bin-path := $(HOME)/.local/bin

ifeq ($(branch),master)
	decker-name := $(base-name)-$(version)
else
	decker-name := $(base-name)-$(version)-$(branch)
endif

ifdef DECKER_DEV
	yarn-mode := development
else
	yarn-mode := production
endif

JS_DEP_COPY = notes/notes.html
JS_DEP_COPY += notes/notes.js
JS_DEP_COPY += reveal.js-menu/menu.js
JS_DEP_COPY += reveal.js-menu/menu.css
JS_DEP_COPY += reveal.js-menu/font-awesome/css/all.css
JS_DEP_COPY += \
	reveal.js-menu/font-awesome/webfonts/fa-solid-900.woff2 \
	reveal.js-menu/font-awesome/webfonts/fa-regular-400.woff2 \
	reveal.js-menu/font-awesome/webfonts/fa-solid-900.woff \
	reveal.js-menu/font-awesome/webfonts/fa-regular-400.woff \
	reveal.js-menu/font-awesome/webfonts/fa-solid-900.ttf \
	reveal.js-menu/font-awesome/webfonts/fa-regular-400.ttf
JS_DEP_COPY += print/paper.css
JS_DEP_COPY += print/pdf.css
JS_DEP_COPY_FULL_PATH = $(addprefix resource/support/, $(JS_DEP_COPY))

build:
	stack build -j 8 --fast

yarn: $(JS_DEP_COPY_FULL_PATH)
	yarn install && yarn run webpack --mode $(yarn-mode)

dist: yarn build
	rm -rf dist
	mkdir -p dist
	ln -s $(executable) dist/$(decker-name) 
	zip -qj dist/$(decker-name).zip dist/$(decker-name)
	rm dist/$(decker-name)

test:
	stack test -j 8 --fast

watch:
	stack test -j 8 --fast --file-watch

clean:
	stack clean
	rm -rf dist
	rm -rf resource/support/*

install: yarn build
	stack exec -- decker clean
	mkdir -p $(local-bin-path)
	cp $(executable) "$(local-bin-path)/$(decker-name)"
	ln -sf "$(decker-name)" $(local-bin-path)/$(base-name)

version:
	@echo "$(decker-name)"

.PHONY: build clean test install dist docs yarn

##### Copy JS dependencies that can't be packed with webpack

resource/support/print/%: node_modules/reveal.js/css/print/%
	mkdir -p $(@D) && cp $< $@

resource/support/notes/%: node_modules/reveal.js/plugin/notes/%
	mkdir -p $(@D) && cp $< $@

resource/support/reveal.js-menu/%: node_modules/reveal.js-menu/%
	mkdir -p $(@D) &&	cp $< $@