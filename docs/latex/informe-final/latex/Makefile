# ============================================================================
# Makefile — Compila el informe LaTeX (pdflatex + bibtex + 2 pasadas finales)
#   make        -> compila el PDF
#   make view   -> compila y abre el PDF
#   make clean  -> borra solo los archivos auxiliares (conserva el PDF)
#   make cleanall -> borra también el PDF
# ============================================================================

MAIN    = main
PDF     = main.pdf

.PHONY: all view clean cleanall

all:
	pdflatex -interaction=nonstopmode $(MAIN).tex
	bibtex $(MAIN)
	pdflatex -interaction=nonstopmode $(MAIN).tex
	pdflatex -interaction=nonstopmode $(MAIN).tex

view: all
	xdg-open $(PDF)

clean:
	rm -f $(MAIN).aux $(MAIN).log $(MAIN).toc $(MAIN).lot $(MAIN).lof $(MAIN).out $(MAIN).bbl $(MAIN).blg $(MAIN).synctex.gz

cleanall: clean
	rm -f $(PDF)
