ikeniborn
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

============================================================
Server 2 Connection Details (Save these for Server 2 setup):
============================================================
Server 1 Address: 129.146.63.189
Port:            443
UUID:            d50a29db-0633-42bf-aab7-7f9bb8cce8dd
Account Name:    server2
============================================================

sudo ./script/setup-vless-server2.sh \
  --server1-address 129.146.63.189 \
  --server1-uuid d50a29db-0633-42bf-aab7-7f9bb8cce8dd \
  --server1-pubkey 392a6352619f2a0d6b4b825e2e8fda14dd00b7a578f45537841a2679243f86de \
  --server1-shortid ebfa2a2d7a605aed

  sudo ./script/test-tunnel-connection.sh --server-type server2 --server1-address 129.146.63.189