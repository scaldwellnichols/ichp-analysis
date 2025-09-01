# See https://nhsdigital.github.io/rap-community-of-practice/training_resources/python/project-structure-and-packaging/

from setuptools import find_packages, setup

setup(
    name='Python Project Template',
    packages=find_packages(),
    version='0.0.1',
    description='',
    author='Scott Caldwell-Nichols',
    license='',
    setup_requires=['pytest-runner','flake8'],
    tests_require=['pytest'],
)