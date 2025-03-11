FROM postgres:16.8

# Install build dependencies and extension packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    postgresql-server-dev-16 \
    postgresql-16-postgis \
    postgresql-16-postgis-scripts \
    postgresql-plpython3-16 \
    postgresql-16-wal2json \
    libkrb5-dev \
    python3-dev \
    python3-full python3-pip python3-venv \
    libpq-dev \
    gcc \
    make \
    wget \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install pgvector
RUN cd /tmp && \
    git clone --branch v0.6.0 https://github.com/pgvector/pgvector.git && \
    cd pgvector && \
    make && \
    make install
# Install pgai with correct paths and debugging
RUN cd /tmp && \
    git clone --branch extension-0.9.0 https://github.com/timescale/pgai.git && \
    cd pgai && \
    projects/extension/build.py install && \
    rm -rf /var/lib/apt/lists/* 

# Install pgjwt
RUN cd /tmp && \
    git clone https://github.com/michelp/pgjwt.git && \
    cd pgjwt && \
    make && \
    make install

# For pgaudit specifically
RUN cd /tmp && \
    git clone https://github.com/pgaudit/pgaudit.git --branch REL_16_STABLE && \
    cd pgaudit && \
    USE_PGXS=1 make && \
    USE_PGXS=1 make install

# Install pg_cron
RUN cd /tmp && \
    git clone https://github.com/citusdata/pg_cron.git && \
    cd pg_cron && \
    make && \
    make install

# Install wal2json
RUN cd /tmp && \
    git clone https://github.com/eulerto/wal2json.git && \
    cd wal2json && \
    make && \
    make install
# Install hypopg (dependency for index_advisor)
RUN cd /tmp && \
    git clone https://github.com/HypoPG/hypopg.git && \
    cd hypopg && \
    make && \
    make install
# Install index_advisor
# Install index_advisor from Supabase fork
RUN cd /tmp && \
    git clone https://github.com/supabase/index_advisor.git && \
    cd index_advisor && \
    make && \
    make install

# Install pg_stat_monitor
RUN cd /tmp && \
    git clone https://github.com/percona/pg_stat_monitor.git && \
    cd pg_stat_monitor && \
    USE_PGXS=1 make && \
    USE_PGXS=1 make install

# Install hashids
RUN cd /tmp && \
    git clone https://github.com/iCyberon/pg_hashids.git && \
    cd pg_hashids && \
    make && \
    make install

# pg_stat_statements is included in PostgreSQL contrib
RUN apt-get update && apt-get install -y postgresql-contrib-16 && \
    rm -rf /var/lib/apt/lists/*


# Install TimescaleDB
RUN apt-get update && \
    apt-get install -y gnupg && \
    echo "deb https://packagecloud.io/timescale/timescaledb/debian/ $(. /etc/os-release; echo $VERSION_CODENAME) main" > /etc/apt/sources.list.d/timescaledb.list && \
    wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey | apt-key add - && \
    apt-get update && \
    apt-get install -y timescaledb-2-postgresql-16 && \
    rm -rf /var/lib/apt/lists/*


# Configure shared_preload_libraries
RUN echo "shared_preload_libraries = 'pg_stat_statements,pg_stat_monitor,pg_cron,pgaudit,timescaledb,wal2json'" >> /usr/share/postgresql/postgresql.conf.sample

EXPOSE 5432

# Add custom configuration files to the container
COPY config/postgresql.conf /etc/postgresql/postgresql.conf
COPY config/pg_hba.conf /etc/postgresql/pg_hba.conf

# Create directory for initialization scripts and copy the init script
COPY init-db.sh /docker-entrypoint-initdb.d/
RUN chmod +x /docker-entrypoint-initdb.d/init-db.sh  # Ensure the script is executable

# Set PostgreSQL config to point to custom configuration
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]