#!/bin/bash

# Update and upgrade the server
sudo apt update -y && sudo apt upgrade -y

# Install Nginx
sudo apt install nginx -y

# Install PHP and necessary extensions
sudo apt install php-fpm php-mysql php-xml php-mbstring -y

# Install MySQL server
sudo apt install mysql-server -y

# Secure MySQL installation
sudo mysql_secure_installation <<EOF

y
0
y
y
y
y
EOF

# Install Composer
sudo apt install curl -y
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer

# Create project directory
sudo mkdir -p /var/www/propertymanagement
sudo chown -R $USER:$USER /var/www/propertymanagement
sudo chmod -R 755 /var/www/propertymanagement

# Create Nginx server block
sudo bash -c 'cat <<EOF > /etc/nginx/sites-available/propertymanagement
server {
    listen 80;
    server_name _;
    root /var/www/propertymanagement/public;

    index index.php index.html index.htm index.nginx-debian.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF'

# Enable the new server block
sudo ln -s /etc/nginx/sites-available/propertymanagement /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Install and set up Laravel
cd /var/www/propertymanagement
composer create-project --prefer-dist laravel/laravel .

# Set permissions for Laravel
sudo chown -R www-data:www-data /var/www/propertymanagement/storage /var/www/propertymanagement/bootstrap/cache
sudo chmod -R 775 /var/www/propertymanagement/storage /var/www/propertymanagement/bootstrap/cache

# Configure MySQL for Laravel
sudo mysql -u root -e "
CREATE DATABASE propertymanagement;
CREATE USER 'propertyuser'@'localhost' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON propertymanagement.* TO 'propertyuser'@'localhost';
FLUSH PRIVILEGES;
"

# Update Laravel .env file with MySQL settings
sed -i 's/DB_DATABASE=laravel/DB_DATABASE=propertymanagement/' /var/www/propertymanagement/.env
sed -i 's/DB_USERNAME=root/DB_USERNAME=propertyuser/' /var/www/propertymanagement/.env
sed -i 's/DB_PASSWORD=/DB_PASSWORD=password/' /var/www/propertymanagement/.env

# Generate Laravel application key
php artisan key:generate

# Set up mail configuration (update with your email service settings)
sed -i 's/MAIL_MAILER=smtp/MAIL_MAILER=smtp/' /var/www/propertymanagement/.env
sed -i 's/MAIL_HOST=mailhog/MAIL_HOST=smtp.example.com/' /var/www/propertymanagement/.env
sed -i 's/MAIL_PORT=1025/MAIL_PORT=587/' /var/www/propertymanagement/.env
sed -i 's/MAIL_USERNAME=null/MAIL_USERNAME=your_email@example.com/' /var/www/propertymanagement/.env
sed -i 's/MAIL_PASSWORD=null/MAIL_PASSWORD=your_email_password/' /var/www/propertymanagement/.env
sed -i 's/MAIL_ENCRYPTION=null/MAIL_ENCRYPTION=tls/' /var/www/propertymanagement/.env
sed -i 's/MAIL_FROM_ADDRESS=null/MAIL_FROM_ADDRESS=your_email@example.com/' /var/www/propertymanagement/.env
sed -i 's/MAIL_FROM_NAME="${APP_NAME}"/MAIL_FROM_NAME="Property Management"/' /var/www/propertymanagement/.env

# Install SAML authentication package for Laravel
composer require aacotroneo/laravel-saml2

# Publish the SAML2 configuration
php artisan vendor:publish --provider="Aacotroneo\Saml2\Saml2ServiceProvider"

# Update SAML settings (use your Azure AD details)
cat <<EOF > /var/www/propertymanagement/config/saml2_settings.php
<?php
return [
    'sp' => [
        'entityId' => 'urn:my-entity-id',
        'assertionConsumerService' => [
            'url' => 'http://your_domain/saml2/acs',
        ],
        'singleLogoutService' => [
            'url' => 'http://your_domain/saml2/sls',
        ],
    ],
    'idp' => [
        'entityId' => 'https://sts.windows.net/your-tenant-id/',
        'singleSignOnService' => [
            'url' => 'https://login.microsoftonline.com/your-tenant-id/saml2',
        ],
        'singleLogoutService' => [
            'url' => 'https://login.microsoftonline.com/your-tenant-id/saml2',
        ],
        'x509cert' => 'your_idp_certificate',
    ],
];
EOF

# Create models and migrations for Property Management
php artisan make:model Property -m
php artisan make:model Tenant -m
php artisan make:model Issue -m
php artisan make:model Invoice -m
php artisan make:model Payment -m

# Define the database schema in migration files
# Example for Property migration
cat <<EOF > database/migrations/xxxx_xx_xx_create_properties_table.php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreatePropertiesTable extends Migration
{
    public function up()
    {
        Schema::create('properties', function (Blueprint \$table) {
            \$table->id();
            \$table->string('name');
            \$table->string('address');
            \$table->text('description')->nullable();
            \$table->timestamps();
        });
    }

    public function down()
    {
        Schema::dropIfExists('properties');
    }
}
EOF

# Run migrations
php artisan migrate

# Create Controllers
php artisan make:controller PropertyController --resource
php artisan make:controller TenantController --resource
php artisan make:controller IssueController --resource
php artisan make:controller InvoiceController --resource
php artisan make:controller PaymentController --resource

# Define routes in routes/web.php
cat <<EOF > routes/web.php
<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\PropertyController;
use App\Http\Controllers\TenantController;
use App\Http\Controllers\IssueController;
use App\Http\Controllers\InvoiceController;
use App\Http\Controllers\PaymentController;

Route::resource('properties', PropertyController::class);
Route::resource('tenants', TenantController::class);
Route::resource('issues', IssueController::class);
Route::resource('invoices', InvoiceController::class);
Route::resource('payments', PaymentController::class);
EOF

# Install and configure the package for PDF generation
composer require barryvdh/laravel-dompdf

# Publish the package configuration
php artisan vendor:publish --provider="Barryvdh\DomPDF\ServiceProvider"

# Create a basic Blade template for invoice PDF
mkdir -p resources/views/invoices
cat <<EOF > resources/views/invoices/pdf.blade.php
<!DOCTYPE html>
<html>
<head>
    <title>Invoice</title>
</head>
<body>
    <h1>Invoice #{{ \$invoice->id }}</h1>
    <p>Property: {{ \$invoice->property->name }}</p>
    <p>Tenant: {{ \$invoice->tenant->name }}</p>
    <p>Amount: {{ \$invoice->amount }}</p>
    <p>Date: {{ \$invoice->date }}</p>
</body>
</html>
EOF

# Generate Invoice PDF in InvoiceController
cat <<EOF > app/Http/Controllers/InvoiceController.php
<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\Invoice;
use Barryvdh\DomPDF\Facade as PDF;

class InvoiceController extends Controller
{
    public function generateInvoice(\$id) {
        \$invoice = Invoice::find(\$id);
        \$pdf = PDF::loadView('invoices.pdf', compact('invoice'));
        return \$pdf->download('invoice.pdf');
    }
}
EOF

# Reload Nginx to apply changes
sudo systemctl reload nginx

echo "Property management website setup is complete."
