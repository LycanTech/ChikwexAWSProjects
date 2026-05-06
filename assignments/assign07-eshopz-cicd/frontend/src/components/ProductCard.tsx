'use client';

import { Product } from '@/lib/api';
import { ShoppingCart } from 'lucide-react';

interface ProductCardProps {
  product: Product;
  onAddToCart: (product: Product) => void;
}

export default function ProductCard({ product, onAddToCart }: ProductCardProps) {
  return (
    <div className="card">
      <div className="bg-gradient-to-br from-blue-100 to-purple-100 h-48 flex items-center justify-center">
        <span className="text-6xl">
          {product.category === 'electronics' ? '💻' : '🎧'}
        </span>
      </div>
      <div className="p-4">
        <div className="flex justify-between items-start mb-2">
          <h3 className="font-semibold text-lg text-gray-800">{product.name}</h3>
          <span className="text-blue-600 font-bold">${product.price}</span>
        </div>
        <p className="text-gray-600 text-sm mb-3 line-clamp-2">{product.description}</p>
        <div className="flex justify-between items-center">
          <span className={`text-sm ${product.stock > 10 ? 'text-green-600' : 'text-orange-500'}`}>
            {product.stock > 10 ? 'In Stock' : `Only ${product.stock} left`}
          </span>
          <button
            onClick={() => onAddToCart(product)}
            className="btn-primary flex items-center space-x-2 text-sm"
          >
            <ShoppingCart className="w-4 h-4" />
            <span>Add</span>
          </button>
        </div>
      </div>
    </div>
  );
}
