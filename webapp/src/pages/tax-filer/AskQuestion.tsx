import { useState, useRef, useEffect } from 'react'
import { Send, Bot, User, Loader2, Sparkles, Brain } from 'lucide-react'
import { useMutation } from '@tanstack/react-query'
import { api } from '../../lib/api'
import ReactMarkdown from 'react-markdown'

interface Message {
  id: string
  role: 'user' | 'assistant'
  content: string
  isLLMAugmented?: boolean
}

export default function AskQuestion() {
  const [messages, setMessages] = useState<Message[]>([])
  const [input, setInput] = useState('')
  const messagesEndRef = useRef<HTMLDivElement>(null)

  // Auto-scroll to bottom when new messages arrive
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  // Build conversation context from recent messages for multi-turn conversations
  const getConversationContext = () => {
    const recentMessages = messages.slice(-6) // Last 3 exchanges
    return recentMessages
      .map(m => `${m.role === 'user' ? 'User' : 'Assistant'}: ${m.content}`)
      .join('\n\n')
  }

  const askMutation = useMutation({
    mutationFn: (question: string) => api.askTaxAssistant(question, getConversationContext()),
    onSuccess: (data) => {
      const assistantMessage: Message = {
        id: Date.now().toString(),
        role: 'assistant',
        content: data.answer,
        isLLMAugmented: data.isLLMAugmented,
      }
      setMessages((prev) => [...prev, assistantMessage])
    },
    onError: () => {
      const errorMessage: Message = {
        id: Date.now().toString(),
        role: 'assistant',
        content: 'Sorry, I encountered an error processing your question. Please try again.',
      }
      setMessages((prev) => [...prev, errorMessage])
    },
  })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!input.trim() || askMutation.isPending) return

    // Add user message
    const userMessage: Message = {
      id: Date.now().toString(),
      role: 'user',
      content: input,
    }
    setMessages((prev) => [...prev, userMessage])
    
    askMutation.mutate(input)
    setInput('')
  }

  const suggestedQuestions = [
    "What deductions can I claim for working from home?",
    "How do I report cryptocurrency gains?",
    "What's the difference between standard and itemized deductions?",
    "Can I deduct student loan interest?",
  ]

  return (
    <div className="h-[calc(100vh-12rem)] flex flex-col">
      {/* Header */}
      <div className="mb-4">
        <h1 className="text-2xl font-bold text-slate-900">Ask a Tax Question</h1>
        <p className="text-slate-600 mt-1">
          Get personalized answers powered by RAG and Azure OpenAI
        </p>
      </div>

      {/* Chat Container */}
      <div className="flex-1 bg-white rounded-xl border border-slate-200 flex flex-col overflow-hidden">
        {/* Messages */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {messages.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center px-4">
              <div className="w-16 h-16 bg-zava-100 rounded-full flex items-center justify-center mb-4">
                <Sparkles className="w-8 h-8 text-zava-600" />
              </div>
              <h3 className="text-lg font-semibold text-slate-900 mb-2">
                AI-Powered Tax Assistant
              </h3>
              <p className="text-slate-600 mb-6 max-w-md">
                Ask any tax-related question and I'll use our knowledge base combined with 
                AI to provide you with a personalized, conversational answer.
              </p>
              
              {/* Suggested Questions */}
              <div className="w-full max-w-lg">
                <p className="text-sm text-slate-500 mb-3">Try asking:</p>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  {suggestedQuestions.map((question, i) => (
                    <button
                      key={i}
                      onClick={() => setInput(question)}
                      className="text-left p-3 text-sm bg-slate-50 hover:bg-slate-100 
                        rounded-lg text-slate-700 transition-colors"
                    >
                      {question}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          ) : (
            messages.map((message) => (
              <div
                key={message.id}
                className={`flex gap-3 ${message.role === 'user' ? 'flex-row-reverse' : ''}`}
              >
                <div className={`w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 ${
                  message.role === 'user' 
                    ? 'bg-zava-100 text-zava-600' 
                    : 'bg-slate-100 text-slate-600'
                }`}>
                  {message.role === 'user' ? (
                    <User className="w-4 h-4" />
                  ) : (
                    <Bot className="w-4 h-4" />
                  )}
                </div>
                <div className={`max-w-[80%] ${message.role === 'user' ? 'text-right' : ''}`}>
                  <div className={`inline-block p-4 rounded-2xl ${
                    message.role === 'user'
                      ? 'bg-zava-600 text-white rounded-br-md'
                      : 'bg-slate-100 text-slate-900 rounded-bl-md'
                  }`}>
                    {message.role === 'assistant' ? (
                      <div className="prose prose-sm prose-slate max-w-none">
                        <ReactMarkdown>{message.content}</ReactMarkdown>
                      </div>
                    ) : (
                      <p className="whitespace-pre-wrap">{message.content}</p>
                    )}
                  </div>
                  
                  {/* LLM Badge */}
                  {message.isLLMAugmented && (
                    <div className="mt-2 flex items-center gap-1 text-xs text-purple-600">
                      <Brain className="w-3 h-3" />
                      <span>AI-generated response</span>
                    </div>
                  )}
                </div>
              </div>
            ))
          )}
          
          {/* Loading indicator */}
          {askMutation.isPending && (
            <div className="flex gap-3">
              <div className="w-8 h-8 rounded-full bg-slate-100 flex items-center justify-center">
                <Bot className="w-4 h-4 text-slate-600" />
              </div>
              <div className="bg-slate-100 rounded-2xl rounded-bl-md p-4 flex items-center gap-2">
                <Loader2 className="w-5 h-5 animate-spin text-slate-400" />
                <span className="text-sm text-slate-500">Thinking...</span>
              </div>
            </div>
          )}
          <div ref={messagesEndRef} />
        </div>

        {/* Input */}
        <form onSubmit={handleSubmit} className="p-4 border-t border-slate-200">
          <div className="flex gap-2">
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Ask a tax question..."
              className="flex-1 px-4 py-3 border border-slate-200 rounded-xl 
                focus:outline-none focus:ring-2 focus:ring-zava-500 focus:border-transparent"
              disabled={askMutation.isPending}
            />
            <button
              type="submit"
              disabled={!input.trim() || askMutation.isPending}
              className="px-4 py-3 bg-zava-600 text-white rounded-xl hover:bg-zava-700 
                disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              <Send className="w-5 h-5" />
            </button>
          </div>
          <p className="mt-2 text-xs text-slate-500 text-center">
            Powered by Azure SQL Hyperscale vector search and Azure OpenAI
          </p>
        </form>
      </div>
    </div>
  )
}
