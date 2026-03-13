#!/bin/bash
source /docker-scripts/common.sh

#-------------------------------------------------------------------------------
# Refresh Apt Cache
#-------------------------------------------------------------------------------
update_apt


#-------------------------------------------------------------------------------
# Build Deps
#-------------------------------------------------------------------------------
print_heading "Installing Build Deps"
apt install -y wget build-essential libreadline-dev zlib1g-dev flex bison libicu-dev pkg-config icu-devtools clang-15 llvm-15
early_exit $?


#-------------------------------------------------------------------------------
# Fetch Repos
#-------------------------------------------------------------------------------
print_heading "Downloading postgres 17.9 source and age 1.7.0"
early_exit $?
wget https://ftp.postgresql.org/pub/source/v17.9/postgresql-17.9.tar.gz
early_exit $?
wget https://dlcdn.apache.org/age/PG17/1.7.0/apache-age-1.7.0-src.tar.gz
early_exit $?

#-------------------------------------------------------------------------------
# Building Postgres
#-------------------------------------------------------------------------------
print_heading "Building Postgres"
tar -xvf postgresql-17.9.tar.gz && tar -xvf apache-age-1.7.0-src.tar.gz
early_exit $?
cd postgresql-17.9 && ./configure
early_exit $?
make install
early_exit $?
print_heading "Bin Placing Headers"
cp -rL src/include/. /usr/include/postgresql/17/server/

#-------------------------------------------------------------------------------
# Building AGE
#-------------------------------------------------------------------------------
print_heading "Installing Age"
cd ../apache-age-1.7.0
make install
early_exit $?

cd .. && rm -rf apache-age* && rm -rf postgresql*


apt remove -y wget build-essential libreadline-dev flex bison pkg-config icu-devtools clang-15


#-------------------------------------------------------------------------------
# Purging Apt Cache
#-------------------------------------------------------------------------------
purge_apt

