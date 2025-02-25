#! /bin/sh

set -u # `-e` omitted intentionally, but i can't remember why exactly :'(
set -o pipefail

source ./env.sh

s3_uri_base="s3://${S3_BUCKET}/${S3_PREFIX}"

if [ -z "$PASSPHRASE" ]; then
  file_type=".dump.tar.gz"
else
  file_type=".dump.tar.gz.gpg"
fi

if [ $# -eq 1 ]; then
  timestamp="$1"
  key_suffix="${POSTGRES_DATABASE}_${timestamp}${file_type}"
else
  echo "Finding latest backup..."
  key_suffix=$(
    aws $aws_args s3 ls "${s3_uri_base}/${POSTGRES_DATABASE}" \
      | sort \
      | tail -n 1 \
      | awk '{ print $4 }'
  )
fi

echo "Fetching backup from S3..."
aws $aws_args s3 cp "${s3_uri_base}/${key_suffix}" "db${file_type}"

if [ -n "$PASSPHRASE" ]; then
  echo "Decrypting backup..."
  gpg --decrypt --batch --yes --passphrase "$PASSPHRASE" db${file_type} > db.dump.tar.gz
  rm "db${file_type}"
fi

pigz -dc db.dump.tar.gz | tar -C db --strip-components 1 -xf -
conn_opts="-h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER"

# TODO: do timescaledb pre-state for professionalism
echo "Restoring from backup..."
pg_restore $conn_opts -Fd -d $POSTGRES_DATABASE db
rm -rf db

echo "Restore complete."
