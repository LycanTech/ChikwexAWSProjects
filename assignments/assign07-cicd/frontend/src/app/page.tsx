'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { getProducts, Product } from '@/lib/api';
import ProductCard from '@/components/ProductCard';
import { ArrowRight, Truck, Shield, CreditCard } from 'lucide-react';

export default function Home() {
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getProducts()
      .then(setProducts)
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  const handleAddToCart = (product: Product) => {
    alert(`Added ${product.name} to cart!`);
  };

  return (
    <div>
      {/* Hero Section */}
      <section className="bg-gradient-to-r from-blue-600 to-purple-600 text-white rounded-2xl p-8 md:p-12 mb-12">
        <div className="max-w-2xl">
          <h1 className="text-4xl md:text-5xl font-bold mb-4">
            Welcome to Chikwex EShopz
          </h1>
          <p className="text-xl text-blue-100 mb-6">
            Discover premium electronics and accessories at unbeatable prices.
          </p>
          <Link href="/products" className="inline-flex items-center space-x-2 bg-white text-blue-600 font-semibold py-3 px-6 rounded-lg hover:bg-blue-50 transition-colors">
            <span>Shop Now</span>
            <ArrowRight className="w-5 h-5" />
          </Link>
        </div>
      </section>

      {/* Features */}
      <section className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
        <div className="flex items-center space-x-4 bg-white p-6 rounded-xl shadow-sm">
          <div className="bg-blue-100 p-3 rounded-full">
            <Truck className="w-6 h-6 text-blue-600" />
          </div>
          <div>
            <h3 className="font-semibold">Free Shipping</h3>
            <p className="text-gray-500 text-sm">On orders over $100</p>
          </div>
        </div>
        <div className="flex items-center space-x-4 bg-white p-6 rounded-xl shadow-sm">
          <div className="bg-green-100 p-3 rounded-full">
            <Shield className="w-6 h-6 text-green-600" />
          </div>
          <div>
            <h3 className="font-semibold">Secure Shopping</h3>
            <p className="text-gray-500 text-sm">100% secure checkout</p>
          </div>
        </div>
        <div className="flex items-center space-x-4 bg-white p-6 rounded-xl shadow-sm">
          <div className="bg-purple-100 p-3 rounded-full">
            <CreditCard className="w-6 h-6 text-purple-600" />
          </div>
          <div>
            <h3 className="font-semibold">Easy Returns</h3>
            <p className="text-gray-500 text-sm">30-day return policy</p>
          </div>
        </div>
      </section>

      {/* Featured Products */}
      <section>
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-2xl font-bold text-gray-800">Featured Products</h2>
          <Link href="/products" className="text-blue-600 hover:text-blue-700 font-medium flex items-center space-x-1">
            <span>View All</span>
            <ArrowRight className="w-4 h-4" />
          </Link>
        </div>

        {loading ? (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            {[1, 2, 3, 4].map((i) => (
              <div key={i} className="card animate-pulse">
                <div className="bg-gray-200 h-48"></div>
                <div className="p-4 space-y-3">
                  <div className="h-4 bg-gray-200 rounded w-3/4"></div>
                  <div className="h-4 bg-gray-200 rounded w-1/2"></div>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            {products.slice(0, 4).map((product) => (
              <ProductCard
                key={product.id}
                product={product}
                onAddToCart={handleAddToCart}
              />
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
