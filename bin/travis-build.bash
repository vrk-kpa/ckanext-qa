#!/bin/bash
set -e
set -x # echo on

echo "This is travis-build.bash..."

echo "Installing the packages that CKAN requires..."
sudo apt-get update -qq
sudo apt-get install solr-jetty libcommons-fileupload-java

echo "Upgrading libmagic for ckanext-qa..."
# appears to upgrade it from 5.09-2 to 5.09-2ubuntu0.6 which seems to help the tests
sudo apt-get install libmagic1

echo "Installing CKAN and its Python dependencies..."
git clone https://github.com/ckan/ckan
cd ckan

if [ $CKANVERSION == 'master' ]
then
    echo "CKAN version: master"
else
    CKAN_TAG=$(git tag | grep ^ckan-$CKANVERSION | sort --version-sort | tail -n 1)
    git checkout $CKAN_TAG
    echo "CKAN version: ${CKAN_TAG#ckan-}"
fi

python setup.py develop
pip install -r requirements.txt --allow-all-external
pip install -r dev-requirements.txt --allow-all-external
cd -

echo "Setting up Solr..."
# solr is multicore for tests on ckan master now, but it's easier to run tests
# on Travis single-core still.
# see https://github.com/ckan/ckan/issues/2972
sed -i -e 's/solr_url.*/solr_url = http:\/\/127.0.0.1:8983\/solr/' ckan/test-core.ini
printf "NO_START=0\nJETTY_HOST=127.0.0.1\nJETTY_PORT=8983\nJAVA_HOME=$JAVA_HOME" | sudo tee /etc/default/jetty
sudo cp ckan/ckan/config/solr/schema.xml /etc/solr/conf/schema.xml
sudo service jetty restart

echo "Creating the PostgreSQL user and database..."
sudo -u postgres psql -c "CREATE USER ckan_default WITH PASSWORD 'pass';"
sudo -u postgres psql -c 'CREATE DATABASE ckan_test WITH OWNER ckan_default;'

echo "Initialising the database..."
cd ckan
paster db init -c test-core.ini
cd -

echo "Installing dependency ckanext-report and its requirements..."
pip install -e git+https://github.com/datagovuk/ckanext-report.git#egg=ckanext-report

echo "Installing dependency ckanext-archiver and its requirements..."
git clone https://github.com/ckan/ckanext-archiver.git
cd ckanext-archiver
pip install -e .
pip install -r requirements.txt
cd -

echo "Installing ckanext-qa and its requirements..."
python setup.py develop
pip install -r requirements.txt
pip install -r dev-requirements.txt

echo "Moving test-core.ini into a subdir..."
mkdir subdir
mv test-core.ini subdir

echo "travis-build.bash is done."
