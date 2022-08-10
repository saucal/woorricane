# Woorricane

WooCommerce won't know what hit it.

## What is it?

Right now it's a simple bash script to load test a WooCommerce site. Given that you have the resources to run this. That means, multiple CPU cores, lots of memory. We've used DO droplets and we were able.

The script is self sufficient so that you only need to drop it in your Ubuntu based server through ftp, and then just run it.

## Requirements

If you run the script as root on linux, it'll install everything it needs. 

If you don't run it as sudo, then you can pre install the following:

* curl
* php7.4-cli
* GNU grep (you'll need to install this in macOS with homebrew)

On the site you're running this on, you'll need to install and activate the [Woorricane Helper plugin](https://github.com/saucal/woorricane-helper)

# Getting Started

Just run the `test.sh` command with the following options:

```
./test.sh --url "https://test.example/" --cart "cart" --checkout "checkout" --product "13" 30 0.01
```

Where

`--url` dictates the site you want to flood

`--cart` dictates the path to the cart page

`--checkout` dictates the path to the checkout page

`--product` dictates the product ID you want to flood the checkout with

`30` (first positional argument) dictates the number of request to throw

`0.01` (second positonal argument) dictates the time to wait before launching a new thread


# Disclaimer

This is currently a WIP. It's not yet tested in a variety of environments, and will definetely have bugs. If you're interested in contributing, please open up an issue or pull request.
