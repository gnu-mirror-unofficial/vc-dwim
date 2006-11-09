dist_man_MANS = $(srcdir)/vc-dwim.1 $(srcdir)/vc-chlog.1
MAINTAINERCLEANFILES = $(dist_man_MANS)

$(srcdir)/vc-dwim.1: $(top_srcdir)/vc-dwim.pl
	perllibdir="`$(am__cd) $(top_srcdir) && pwd`" \
	$(HELP2MAN) -o $@ ../vc-dwim
$(srcdir)/vc-chlog.1: $(top_srcdir)/vc-chlog.in
	$(HELP2MAN) -o $@ ../vc-chlog
