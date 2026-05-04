'use client';

import Link from 'next/link';
import { ShoppingCart, User, Package, Home } from 'lucide-react';

export default function Header() {
  return (
    <header className="bg-blue-600 text-white shadow-lg">
      <div className="container mx-auto px-4">
        <div className="flex items-center justify-between h-16">
          <Link href="/" className="flex items-center space-x-2">
            <Package className="w-8 h-8" />
            <span className="text-xl font-bold">Chikwex EShopz</span>
          </Link>

          <nav className="hidden md:flex items-center space-x-8">
            <Link href="/" className="flex items-center space-x-1 hover:text-blue-200 transition-colors">
              <Home className="w-4 h-4" />
              <span>Home</span>
            </Link>
            <Link href="/products" className="hover:text-blue-200 transition-colors">
              Products
            </Link>
            <Link href="/orders" className="hover:text-blue-200 transition-colors">
              Orders
            </Link>
          </nav>

          <div className="flex items-center space-x-4">
            <Link href="/cart" className="relative hover:text-blue-200 transition-colors">
              <ShoppingCart className="w-6 h-6" />
              <span className="absolute -top-2 -right-2 bg-red-500 text-white text-xs rounded-full w-5 h-5 flex items-center justify-center">
                0
              </span>
            </Link>
            <Link href="/login" className="flex items-center space-x-1 hover:text-blue-200 transition-colors">
              <User className="w-5 h-5" />
              <span className="hidden sm:inline">Login</span>
            </Link>
          </div>
        </div>
      </div>
    </header>
  );
}
