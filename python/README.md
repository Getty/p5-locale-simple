# Description
This is a small wrapper around Gettext functionality that integrates sprintf and makes it a bit more easy to setup the internationalization. It ONLY supports UTF8 data, and in or output, that is a fixed setup (and always will be).

# Usage

Usage of this module is very similar to that of [Locale::Simple](https://metacpan.org/module/Locale::Simple):

    from locale_simple import *
    
    # Set the locale dir
    l_dir('data/locale')
    # Set the default domain
    ltd('test')
    # Set the default language
    l_lang('de_DE')

    print l("Hello") # Hallo
    print ln("You have %d message","You have %d messages",1) # Du hast 1 Nachricht
