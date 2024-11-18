# Requires:
# - make (to run this)
# - openssh (for easyrsa and expiry checks)
# - aws cli (to push CRL certificate)

ifndef VERBOSE
.SILENT:
endif

define USAGE
make debug-server
  Check the status of the current VPN configuration
make current
  Shows the current connection
make available
  Lists the available connections to restore
make new-server name=NAME
  Initializes a new client VPN certificate
  name: A readable name for the endpoint. Will be used as the common name for the certificate. Is saved to pki/vpn_name. [.a-z_-] e.g. vpn.buy.nsw.gov.au
make renew-server
  Renews an existing client VPN certificate
make archive
  Backs up the current configuration up to a zip file named NAME.DATE.zip and removes its pki directory
make restore name=NAME [date=YYYYMMDD] [proceed=1]
  Restores an archive for that VPN to pki. If `proceed=1` is not included, this only lists the archive that would be restored.
make debug-client [name=NAME]
  Check the status of one or all client VPN configurations
make new-client name=NAME
  Creates a client certificate for connecting to the VPN
  name: Typically the name of the developer. [.a-z_-] e.g. blair, blair_mckenzie
make renew-client name=NAME
  Renews a client certificate
  name: The name of the client certificate
make generate-crl
  Regenerates the certificate revocation list certificate
make push-crl profile=AWSPROFILE [proceed=1]
  Regenerates the certificate revocation list certificate
make cat-crl
  Outputs the current CRL certificate
make purge-client name=NAME [proceed=1]
  Removes the files relevant to a client. If `proceed=1` is not included, this only lists the files that would be removed.
  name: The name of the client certificate
make purge-server [proceed=1]
  Removes the pki directory. If `proceed=1` is not included, this only lists the number of files that would be removed.
make purge-backups [proceed=1]
  Removes backups. If `proceed=1` is not included, this only lists the number of files that would be removed.
endef
export USAGE

default:
	@echo "$$USAGE"

debug-server:
	cd easyrsa3;\
	if [ ! -d "pki" ]; then\
		echo "./easyrsa3/pki directory:       Does not exist. This must contain a current easyrsa configuration.";\
	else\
		echo "./easyrsa3/pki directory:       Exists";\
		if [ ! -f "pki/vpn_id" ]; then\
			echo "./easyrsa3/pki/vpn_id file:     Does not exist. This must contain the Client VPN endpoint ID.";\
		else\
			VPN_ID=$$(cat pki/vpn_id);\
			echo "./easyrsa3/pki/vpn_id file:     $$VPN_ID";\
		fi;\
		if [ ! -f "pki/vpn_region" ]; then\
			echo "./easyrsa3/pki/vpn_region file: Does not exist. This must should contain the region of the endpoint, for pushing CRL certficiates.";\
		else\
			VPN_REGION=$$(cat pki/vpn_region);\
			echo "./easyrsa3/pki/vpn_region file: $$VPN_REGION";\
		fi;\
		if [ ! -f "pki/vpn_name" ]; then\
			echo "./easyrsa3/pki/vpn_name file:   Does not exist. This must contain the name of the VPN.";\
		else\
			VPN_NAME=$$(cat pki/vpn_name);\
			echo "./easyrsa3/pki/vpn_name file:   $$VPN_NAME";\
			echo "Server: $$(openssl x509 -enddate -noout -in ./pki/issued/$$VPN_NAME.crt)";\
		fi;\
		echo "CRL: $$(openssl crl -in .//pki/crl.pem -text | grep 'Next Update')";\
	fi

current:
	cd easyrsa3;\
	if [ ! -f "pki/vpn_name" ]; then\
		echo "There is no current server";\
	else\
		VPN_NAME=$$(cat pki/vpn_name);\
		echo "The current server is $$VPN_NAME";\
	fi

available:
	cd easyrsa3;\
	FILES=$$(find . -maxdepth 1 -type f -name '*.zip' | grep -oP '^\./\K.+(?=\.[0-9]{8}\.zip)');\
	UNIQUE_CODES=$$(echo "$$FILES" | sort -u);\
	for code in $$UNIQUE_CODES; do\
		LATEST_FILE=$$(ls $$code.*.zip | sort -r | head -n 1);\
		CLIENT_CODE=$${LATEST_FILE%.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].zip};\
		DATE=$${LATEST_FILE%.zip};\
		DATE=$${DATE##*.};\
		echo "$$CLIENT_CODE:$$DATE ('make restore name=$$CLIENT_CODE date=$$DATE')";\
	done;\
	if [ -f "pki/vpn_name" ]; then\
		echo "There is an existing server open (see 'make current'). You will need to archive it before restoring another (see 'make archive').";\
	fi;

new-server:
	cd easyrsa3;\
	if [ -d "pki" ]; then\
		echo "There is an existing ./easyrsa3/pki directory. Run 'make archive' or 'make purge-server' first.";\
	elif [ "$(name)" = "" ]; then\
		echo "name is not specified";\
	else\
		./easyrsa init-pki;\
		EASYRSA_REQ_CN="$(name)";\
		./easyrsa --batch build-ca nopass;\
		./easyrsa build-server-full $(name) nopass;\
		echo "$(name)" >pki/vpn_name;\
		echo "Created certificate for $(name). Find the following files for importing into AWS Certificate Manager:";\
		echo "- Certificate body: easyrsa3/pki/issued/$(name).crt";\
		echo "- Certificate private key: easyrsa3/pki/private/$(name).key";\
		echo "- Certificate chain: easyrsa3/pki/ca.crt";\
		echo "Once the endpoint has been set up, download the client config ('downloaded-client-config.ovpn')";\
		echo "to the pki directory. You will then be able to create client certificates with 'make new-client name=bob'.";\
	fi

renew-server:
	cd easyrsa3;\
	if [ ! -f "pki/vpn_name" ]; then\
		echo "There is no ./easyrsa3/pki directory";\
	else\
		VPN_NAME=$$(cat pki/vpn_name);\
		./easyrsa renew $$VPN_NAME nopass;\
		echo "Updated certificate for $$VPN_NAME. Find the following files for importing into AWS Certificate Manager:";\
		echo "- Certificate body: easyrsa3/pki/issued/$$VPN_NAME.crt";\
		echo "- Certificate private key: easyrsa3/pki/private/$$VPN_NAME.key";\
		echo "- Certificate chain: easyrsa3/pki/ca.crt";\
		echo "Note that you should not need to recreate the client certficiates, but if you choose to then download the";\
		echo "updated client config ('downloaded-client-config.ovpn') to the pki directory first.";\
	fi

# TODO: in theory it should be possible to push the new certificates using the CLI:
# aws acm import-certificate --certificate fileb://Certificate.pem \
#  --certificate-chain fileb://CertificateChain.pem \
#  --private-key fileb://PrivateKey.pem \
#  --certificate-arn arn:aws:acm:region:123456789012:certificate/12345678-1234-1234-1234-12345678901
# Need to test this though.
# Would work the same way as push-crl. profile+proceed paramaters; certificate id as a file in pki.
# I guess the initial cert creation could be a command too.

archive:
	cd easyrsa3;\
	if [ ! -d "pki" ]; then\
		echo "There is no ./easyrsa3/pki directory";\
	else\
		VPN_NAME=$$(cat pki/vpn_name);\
		DT=$$(date +"%Y%m%d");\
		zip -r $$VPN_NAME.$$DT.zip ./pki;\
		echo "Archived to easyrsa3/$$VPN_NAME.$$DT.zip";\
		rm -rf pki;\
		echo "Removed pki directory";\
	fi

restore:
	cd easyrsa3;\
	if [ -f "pki/vpn_name" ]; then\
		echo "There is an existing ./easyrsa3/pki directory";\
	elif [ "$(name)" = "" ]; then\
		echo "name is not specified";\
	elif [ "$(date)" = "" ]; then\
		if [ "$$(ls -r $(name).*.zip | head -1)" = "" ]; then\
			echo "Backup not found";\
		elif [ "$(proceed)" != "1" ]; then\
			echo "Found backup: $$(ls -r $(name).*.zip | head -1). Run 'make restore name=$(name) proceed=1' to continue.";\
		else\
			unzip -uo $$(ls -r $(name).*.zip | head -1);\
		fi;\
	elif [ "$$(ls -r $(name).$(date).zip | head -1)" = "" ]; then\
		echo "Backup not found";\
	elif [ "$(proceed)" != "1" ]; then\
		echo "Found backup: $$(ls -r $(name).$(date).zip | head -1). Run 'make restore name=$(name) date=$(date) proceed=1' to continue.";\
	else\
		unzip -uo $$(ls -r $(name).$(date).zip | head -1);\
	fi;

debug-client:
	cd easyrsa3;\
	if [ ! -d "pki" ]; then\
	    echo "There is no ./easyrsa3/pki directory. This must contain a current easyrsa configuration.";\
	elif [ ! -f "pki/vpn_name" ]; then\
		echo "The ./easyrsa3/pki/vpn_name file does not exist";\
	else\
	    VPN_NAME=$$(cat pki/vpn_name);\
		\
		if [ "$(name)" = "" ]; then\
			FILES=$$(ls pki/*.$${VPN_NAME}.ovpn | sed "s/\.$${VPN_NAME}\.ovpn$$//" | sed "s/^pki\///");\
			echo "Client certificate status:";\
			for file in $$FILES; do\
				echo "- $$file: $$(openssl x509 -enddate -noout -in ./pki/issued/$${file}.$${VPN_NAME}.crt)";\
			done;\
		else\
		    echo "Client certificate: $$(openssl x509 -enddate -noout -in ./pki/issued/$(name).$${VPN_NAME}.crt)";\
		fi;\
	fi

list-clients:
	cd easyrsa3;\
	if [ ! -d "pki" ]; then\
	    echo "There is no ./easyrsa3/pki directory. This must contain a current easyrsa configuration.";\
	elif [ ! -f "pki/vpn_name" ]; then\
		echo "The ./easyrsa3/pki/vpn_name file does not exist";\
	else\
	    VPN_NAME=$$(cat pki/vpn_name);\
		FILES=$$(ls pki/*.$${VPN_NAME}.ovpn | sed "s/\.$${VPN_NAME}\.ovpn$$//" | sed "s/^pki\///");\
		echo "Clients:";\
		for file in $$FILES; do\
			echo "- $$file";\
		done;\
	fi

new-client:
	cd easyrsa3;\
	if [ ! -f "pki/vpn_name" ]; then\
		echo "There is no ./easyrsa3/pki directory";\
	elif [ "$(name)" = "" ]; then\
		echo "name is not specified";\
	elif [ ! -f "pki/downloaded-client-config.ovpn" = "" ]; then\
		echo "downloaded-client-config.ovpn missing from pki directory";\
	else\
		VPN_NAME=$$(cat pki/vpn_name);\
		\
		echo "Building new client certificate for $${VPN_NAME}";\
		./easyrsa build-client-full $(name).$${VPN_NAME} nopass;\
		\
		echo "Generating OVPN file";\
		OVPN_FILE=pki/$(name).$${VPN_NAME}.ovpn;\
		cp pki/downloaded-client-config.ovpn $$OVPN_FILE;\
		echo "" >>$$OVPN_FILE;\
		echo "<cert>" >>$$OVPN_FILE;\
		awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' pki/issued/$(name).$${VPN_NAME}.crt >>$$OVPN_FILE;\
		echo "</cert>" >>$$OVPN_FILE;\
		echo "<key>" >>$$OVPN_FILE;\
		cat pki/private/$(name).$${VPN_NAME}.key >>$$OVPN_FILE;\
		echo "</key>" >>$$OVPN_FILE;\
		\
		echo "Creating client archive";\
		DT=$$(date +"%Y%m%d");\
		zip -j pki/$(name).$$VPN_NAME.$$DT.zip $$OVPN_FILE;\
	fi

renew-client:
	cd easyrsa3;\
	if [ ! -f "pki/vpn_name" ]; then\
		echo "There is no ./easyrsa3/pki directory";\
	elif [ "$(name)" = "" ]; then\
		echo "name is not specified";\
	else\
		VPN_NAME=$$(cat pki/vpn_name);\
		\
		echo "Renewing client certificate for $${VPN_NAME}";\
		./easyrsa renew $(name).$${VPN_NAME} nopass;\
		\
		echo "Generating OVPN file";\
		OVPN_FILE=pki/$(name).$${VPN_NAME}.ovpn;\
		cp pki/downloaded-client-config.ovpn $$OVPN_FILE;\
		echo "" >>$$OVPN_FILE;\
		echo "<cert>" >>$$OVPN_FILE;\
		awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' pki/issued/$(name).$${VPN_NAME}.crt >>$$OVPN_FILE;\
		echo "</cert>" >>$$OVPN_FILE;\
		echo "<key>" >>$$OVPN_FILE;\
		cat pki/private/$(name).$${VPN_NAME}.key >>$$OVPN_FILE;\
		echo "</key>" >>$$OVPN_FILE;\
		\
		echo "Creating client archive";\
		DT=$$(date +"%Y%m%d");\
		zip -j pki/$(name).$$VPN_NAME.$$DT.zip $$OVPN_FILE;\
	fi

revoke-client:
	cd easyrsa3;\
	if [ ! -f "pki/vpn_name" ]; then\
		echo "There is no ./easyrsa3/pki directory";\
	elif [ "$(name)" = "" ]; then\
		echo "name is not specified";\
	else\
		VPN_NAME=$$(cat pki/vpn_name);\
		\
		./easyrsa revoke $(name).$${VPN_NAME};\
		\
		echo "Client revoked. See `make generate-crl` and `make push-crl`.";\
	fi;

generate-crl:
	cd easyrsa3;\
	./easyrsa gen-crl;\
	echo "Upload the content of the above file as the new client revocation list. See 'make push-crl'.";

push-crl:
	cd easyrsa3;\
	if [ ! -f "pki/vpn_id" ]; then\
		echo "There is no ./easyrsa3/pki/vpn_id file. This must contain the Client VPN endpoint ID";\
	elif [ ! -f "pki/vpn_region" ]; then\
		echo "There is no ./easyrsa3/pki/vpn_region file. This must contain the region of the endpoint";\
	elif [ "$(profile)" = "" ]; then\
		echo "profile is not specified";\
	else\
		VPN_ID=$$(cat pki/vpn_id);\
		VPN_REGION=$$(cat pki/vpn_region);\
		\
		if [ "$(proceed)" = "" ]; then\
			echo "CRL would be pushed to $${VPN_ID} in $${VPN_REGION}";\
			echo "Run 'make push-crl profile=$(profile) proceed=1' to continue";\
		else\
			aws --profile "${profile}" ec2 import-client-vpn-client-certificate-revocation-list --certificate-revocation-list file://pki/crl.pem --client-vpn-endpoint-id $${VPN_ID} --region $${VPN_REGION};\
			\
			echo "CRL is updated. It may take a minute or two for connections to reflect the change.";\
		fi;\
	fi

cat-crl:
	cat easyrsa3/pki/crl.pem

purge-client:
	cd easyrsa3;\
	if [ ! -f "pki/vpn_name" ]; then\
		echo "There is no ./easyrsa3/pki directory";\
	elif [ "$(name)" = "" ]; then\
		echo "name is not specified";\
	elif [ "$(proceed)" != "1" ]; then\
		VPN_NAME=$$(cat pki/vpn_name);\
		FILES=$$(ls pki/reqs/$(name).$$VPN_NAME.req pki/private/$(name).$$VPN_NAME.key pki/issued/$(name).$$VPN_NAME.crt pki/$(name).$$VPN_NAME.*);\
		echo $$FILES;\
		if [ -z "$$FILES" ]; then\
			echo "No client files found";\
		else\
			echo "The following files will be removed:";\
			for file in $$FILES; do\
				echo "- $$file";\
			done;\
			echo "Run 'make purge-client name=$(name) proceed=1' to continue";\
		fi;\
	else\
		VPN_NAME=$$(cat pki/vpn_name);\
		FILES=$$(ls pki/reqs/$(name).$$VPN_NAME.req pki/private/$(name).$$VPN_NAME.key pki/issued/$(name).$$VPN_NAME.crt pki/$(name).$$VPN_NAME.*);\
		rm pki/reqs/$(name).$$VPN_NAME.req pki/private/$(name).$$VPN_NAME.key pki/issued/$(name).$$VPN_NAME.crt pki/$(name).$$VPN_NAME.*;\
		echo "Removed:";\
		for file in $$FILES; do\
			echo "- $$file";\
		done;\
	fi;

purge-server:
	if [ ! -d "easyrsa3/pki" ]; then\
		echo "There is no ./easyrsa3/pki directory";\
	elif [ "$(proceed)" != "1" ]; then\
		FILES=$$(ls -R easyrsa3/pki/);\
		echo "$${#FILES[@]} files will be removed";\
		echo "Run 'make purge-server proceed=1' to continue";\
	else\
		rm -rf easyrsa3/pki;\
		echo "Removed pki directory";\
	fi

purge-backups:
	if [ "$(proceed)" != "1" ]; then\
		FILES=$$(ls easyrsa3/pki/*.zip);\
		echo "$${#FILES[@]} files will be removed";\
		echo "Run 'make purge-backups proceed=1' to continue";\
	else\
		rm -rf easyrsa3/*.zip;\
		echo "Removed backups";\
	fi


