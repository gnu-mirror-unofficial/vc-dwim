dist_man_MANS = $(srcdir)/vc-dwim.1 $(srcdir)/vc-chlog.1
MAINTAINERCLEANFILES = $(dist_man_MANS)

$(srcdir)/vc-dwim.1: $(top_srcdir)/vc-dwim.pl
	$(AM_V_GEN)$(POD2MAN) ../vc-dwim $@
$(srcdir)/vc-chlog.1: $(top_srcdir)/vc-chlog.in
	$(AM_V_GEN)$(HELP2MAN) -o $@ ../vc-chlog
