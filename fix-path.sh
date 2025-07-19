#!/bin/bash

# Fix PATH cache after VPN installation
echo "Fixing PATH cache issue..."
hash -r
echo "Done! Now you can use 'vpn' command."