from setuptools import setup
from python.locale_simple import __version__
import os, sys

long_description = open('python/README.md').read()

version = os.getenv('V')
if not version and 'bdist' in sys.argv: raise ValueError('You must set the environmental variable $V (the version number) to release.')

setup(name='locale-simple',
      version=str(version),
      py_modules=['locale_simple'],
      package_dir={'':'python'},
      description='Python verrsion of Locale::Simple, Translation system based on gettext storage, same API in Perl and Javascript',
      author='Michael Smith',
      author_email='crazedpsyc@duckduckgo.com',
      license='PerlArtistic',
      url='https://github.com/Getty/p5-locale-simple/',
      long_description=long_description,
      platforms=['any'],
      classifiers=["Development Status :: 4 - Beta",
                   "Intended Audience :: Developers",
                   "Operating System :: OS Independent",
                   "Programming Language :: Python",
                   "Topic :: Software Development :: Localization",
                   ],
      )
