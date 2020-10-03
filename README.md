# Woorricane

WooCommerce won't know what hit it.

## What is it?

Right now it's a simple bash script to load test a WooCommerce site. Given that you have the resources to run this. That means, multiple CPU cores, lots of memory. We've used DO droplets and we were able.

The script is self sufficient so that you only need to drop it in your Ubuntu based server through ftp, and then just run it.

## Requirements

If you run the script as root, it'll install everything it needs. 

If you don't run it as sudo, then you can pre install the following:

* curl
* php7.4-cli

# Disclaimer

This is currently a WIP. It's not yet tested in a variety of environments, and will definetely have bugs. If you're interested in contributing, please open up an issue or pull request.