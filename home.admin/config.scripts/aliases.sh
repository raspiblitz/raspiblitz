# aliases.sh

alias cl='sudo -u bitcoin /usr/local/bin/lightning-cli --conf=/home/bitcoin/.lightning/config'
alias lightning-cli='sudo -u bitcoin /usr/local/bin/lightning-cli --conf=/home/bitcoin/.lightning/config'
alias lit-frcli='sudo -u lit frcli --rpcserver=localhost:8443     --tlscertpath=/home/lit/.lit/tls.cert     --macaroonpath=/home/lit/.faraday/mainnet/faraday.macaroon'
alias lit-loop='sudo -u lit loop --rpcserver=localhost:8443 \
    --tlscertpath=/home/lit/.lit/tls.cert \	
    --macaroonpath=/home/lit/.loop/mainnet/loop.macaroon'
alias lit-pool='sudo -u lit pool --rpcserver=localhost:8443     --tlscertpath=/home/lit/.lit/tls.cert \	
    --macaroonpath=/home/lit/.pool/mainnet/pool.macaroon'
alias ls='ls --color=auto'
alias scl='sudo -u bitcoin /usr/local/bin/lightning-cli --conf=/home/bitcoin/.lightning/sconfig'
alias slightning-cli='sudo -u bitcoin /usr/local/bin/lightning-cli --conf=/home/bitcoin/.lightning/sconfig'
alias tcl='sudo -u bitcoin /usr/local/bin/lightning-cli --conf=/home/bitcoin/.lightning/tconfig'
alias tlightning-cli='sudo -u bitcoin /usr/local/bin/lightning-cli --conf=/home/bitcoin/.lightning/tconfig'